import { Filesystem, Directory } from '@capacitor/filesystem';
import { LocalSong } from './db';
import { extractMetadata } from './metadata';

// Helper to check if running inside a Capacitor Native App container
export function isCapacitorActive(): boolean {
  return typeof window !== 'undefined' && (window as any).Capacitor !== undefined;
}

// Convert a native file URI to a playable web-safe URL inside Capacitor
export async function getCapacitorPlayUrl(filePath: string): Promise<string> {
  if (!isCapacitorActive()) return '';
  try {
    const fileResult = await Filesystem.getUri({
      path: filePath,
      directory: Directory.ExternalStorage
    });
    return (window as any).Capacitor.convertFileSrc(fileResult.uri);
  } catch (e) {
    console.error('Failed to resolve Capacitor play URL for path:', filePath, e);
    return '';
  }
}

// Check and request storage permissions on Android/iOS
export async function requestMobileStoragePermission(): Promise<boolean> {
  if (!isCapacitorActive()) return false;
  try {
    const status = await Filesystem.checkPermissions();
    if (status.publicStorage === 'granted') {
      return true;
    }
    const request = await Filesystem.requestPermissions();
    return request.publicStorage === 'granted';
  } catch (e) {
    console.error('Failed to request mobile storage permission:', e);
    return false;
  }
}

interface MobileScanProgress {
  scannedCount: number;
  totalFiles: number;
  currentFileName: string;
}

// Recursively scans a directory path on mobile using Capacitor Filesystem
export async function scanMobileDirectory(
  directory: Directory,
  folderPath: string,
  onProgress?: (progress: MobileScanProgress) => void
): Promise<LocalSong[]> {
  const songs: LocalSong[] = [];
  const filesToProcess: string[] = [];

  // Helper to recursively collect files
  async function collectFiles(path: string) {
    try {
      const result = await Filesystem.readdir({
        path,
        directory
      });

      if (result && result.files) {
        for (const file of result.files) {
          const fullPath = path ? `${path}/${file.name}` : file.name;
          if (file.type === 'directory') {
            // Skip system/hidden folders to prevent crashes
            if (!file.name.startsWith('.') && !['Android', 'System Volume Information', 'LOST.DIR'].includes(file.name)) {
              await collectFiles(fullPath);
            }
          } else {
            const ext = file.name.split('.').pop()?.toLowerCase();
            if (ext && ['mp3', 'flac', 'wav', 'ogg', 'm4a'].includes(ext)) {
              filesToProcess.push(fullPath);
            }
          }
        }
      }
    } catch (e) {
      console.warn(`[MobileScan] Could not read path: ${path}`, e);
    }
  }

  // Start collection
  try {
    await collectFiles(folderPath);
  } catch (e) {
    console.warn(`[MobileScan] Initial collect failed for path: ${folderPath}`, e);
  }

  const totalFiles = filesToProcess.length;
  let scannedCount = 0;

  // Process files to extract metadata
  for (const filePath of filesToProcess) {
    scannedCount++;
    const fileName = filePath.split('/').pop() || filePath;

    if (onProgress) {
      onProgress({
        scannedCount,
        totalFiles,
        currentFileName: fileName
      });
    }

    try {
      // Get URI first
      const fileResult = await Filesystem.getUri({ path: filePath, directory });
      const webUrl = (window as any).Capacitor.convertFileSrc(fileResult.uri);

      // Do NOT read whole file as base64 on mobile! This crashes the Android JVM on large MP3 files (e.g. 5MB-10MB).
      // Instead, we just read the first 128KB to parse ID3 metadata using a stream/slice if possible,
      // or fallback to basic file name. This prevents OutOfMemory errors and makes scanning 100x faster!
      let parsedTitle = fileName.replace(/\.[^/.]+$/, "");
      let parsedArtist = 'Unknown Artist';
      let parsedAlbum = 'Unknown Album';
      let parsedCover: string | null = null;

      try {
        // Read small chunk (first 128KB) for metadata to prevent crashes
        // Typecast options to any because older @capacitor/filesystem typings might not have length/offset defined
        const fileChunk = await Filesystem.readFile({
          path: filePath,
          directory,
          length: 131072, // 128 KB
          offset: 0
        } as any);

        if (fileChunk && fileChunk.data) {
          // Convert base64 chunk to blob
          const response = await fetch(`data:audio/mp3;base64,${fileChunk.data}`);
          const blob = await response.blob();
          const fileObject = new File([blob], fileName, { type: blob.type });
          
          // Import dynamic tag reader or fallback
          const { parseID3Tags } = await import('./metadata');
          const tags = await parseID3Tags(fileObject);
          
          if (tags.title) parsedTitle = tags.title;
          if (tags.artist) parsedArtist = tags.artist;
          if (tags.album) parsedAlbum = tags.album;
          if (tags.cover) parsedCover = tags.cover;
        }
      } catch (metadataError) {
        console.warn(`[MobileScan] Metadata extraction skipped for ${fileName}, using filename fallback`, metadataError);
      }

      songs.push({
        id: `mobile-${filePath}`,
        title: parsedTitle,
        artist: parsedArtist,
        album: parsedAlbum,
        duration: 180, // Default fallback duration (will update dynamically upon load loadedmetadata)
        cover: parsedCover,
        fileHandle: null as any,
        path: filePath,
        fileSize: 0,
        addedAt: Date.now(),
        isCloud: false,
        audioUrl: webUrl
      });
    } catch (e) {
      console.error(`[MobileScan] Failed to process: ${filePath}`, e);
    }
  }

  return songs;
}

// Scans all standard device storage locations on mobile (Android/iOS)
export async function scanAllMobileStorage(
  onProgress?: (progress: MobileScanProgress) => void
): Promise<LocalSong[]> {
  const songs: LocalSong[] = [];
  
  // Standard folders to scan on mobile devices
  const foldersToScan = [
    { dir: Directory.ExternalStorage, path: '' }, // Root of External Storage (e.g. /sdcard/) - scans EVERYTHING!
    { dir: Directory.ExternalStorage, path: 'Music' },
    { dir: Directory.ExternalStorage, path: 'Download' },
    { dir: Directory.ExternalStorage, path: 'Documents' },
    { dir: Directory.Documents, path: '' } // iOS/Android App Documents directory
  ];

  // Use a map to prevent duplicates
  const songMap = new Map<string, LocalSong>();
  let totalCollectedFiles = 0;
  
  for (const folder of foldersToScan) {
    try {
      const results = await scanMobileDirectory(folder.dir, folder.path, (progress) => {
        if (onProgress) {
          onProgress({
            scannedCount: songMap.size + progress.scannedCount,
            totalFiles: totalCollectedFiles + progress.totalFiles,
            currentFileName: progress.currentFileName
          });
        }
      });
      
      results.forEach(song => {
        if (!songMap.has(song.id)) {
          songMap.set(song.id, song);
        }
      });
      totalCollectedFiles += results.length;
    } catch (e) {
      console.warn(`[MobileScan] Folder scanning skipped: ${folder.path}`, e);
    }
  }

  return Array.from(songMap.values());
}
