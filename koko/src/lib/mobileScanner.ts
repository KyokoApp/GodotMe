import { Filesystem, Directory } from '@capacitor/filesystem';
import { Device } from '@capacitor/device';
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
    // Convert file:// URI to Capacitor WebView safe URL (e.g. localhost:8080/_capacitor_file_///...)
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

      for (const file of result.files) {
        const fullPath = path ? `${path}/${file.name}` : file.name;
        if (file.type === 'directory') {
          // Skip system/hidden folders to prevent crashes
          if (!file.name.startsWith('.') && !['Android', 'System Volume Information'].includes(file.name)) {
            await collectFiles(fullPath);
          }
        } else {
          const ext = file.name.split('.').pop()?.toLowerCase();
          if (ext && ['mp3', 'flac', 'wav', 'ogg', 'm4a'].includes(ext)) {
            filesToProcess.push(fullPath);
          }
        }
      }
    } catch (e) {
      console.warn(`[MobileScan] Could not read path: ${path}`, e);
    }
  }

  // Start collection
  await collectFiles(folderPath);

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
      // Read file as binary/blob to extract ID3 tags
      const fileRead = await Filesystem.readFile({
        path: filePath,
        directory
      });

      // Convert base64 read data to a JS File object for jsmediatags
      const response = await fetch(`data:audio/mp3;base64,${fileRead.data}`);
      const blob = await response.blob();
      const fileObject = new File([blob], fileName, { type: blob.type });

      const metadata = await extractMetadata(fileObject);
      const webUrl = (window as any).Capacitor.convertFileSrc(
        (await Filesystem.getUri({ path: filePath, directory })).uri
      );

      songs.push({
        id: `mobile-${filePath}`,
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        duration: metadata.duration || 180, // fallback if loadedmetadata duration failed
        cover: metadata.cover,
        fileHandle: null as any, // No FileSystemFileHandle on mobile
        path: filePath,
        fileSize: blob.size,
        addedAt: Date.now(),
        isCloud: false,
        audioUrl: webUrl // Set Capacitor safe web URL directly for playback
      });
    } catch (e) {
      console.error(`[MobileScan] Failed to process metadata for: ${filePath}`, e);
      // Fallback with basic name if parsing failed
      try {
        const fileResult = await Filesystem.getUri({ path: filePath, directory });
        const webUrl = (window as any).Capacitor.convertFileSrc(fileResult.uri);
        const baseName = fileName.replace(/\.[^/.]+$/, "");
        songs.push({
          id: `mobile-${filePath}`,
          title: baseName,
          artist: 'Unknown Artist',
          album: 'Unknown Album',
          duration: 180,
          cover: null,
          fileHandle: null as any,
          path: filePath,
          fileSize: 0,
          addedAt: Date.now(),
          isCloud: false,
          audioUrl: webUrl
        });
      } catch (innerErr) {
        console.error(`[MobileScan] Complete failure on: ${filePath}`, innerErr);
      }
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
    { dir: Directory.ExternalStorage, path: 'Music' },
    { dir: Directory.ExternalStorage, path: 'Download' },
    { dir: Directory.ExternalStorage, path: 'Documents' },
    { dir: Directory.Documents, path: '' } // iOS/Android App Documents directory
  ];

  let totalCollectedFiles = 0;
  
  for (const folder of foldersToScan) {
    try {
      const results = await scanMobileDirectory(folder.dir, folder.path, (progress) => {
        if (onProgress) {
          onProgress({
            scannedCount: songs.length + progress.scannedCount,
            totalFiles: totalCollectedFiles + progress.totalFiles,
            currentFileName: progress.currentFileName
          });
        }
      });
      songs.push(...results);
      totalCollectedFiles += results.length;
    } catch (e) {
      console.warn(`[MobileScan] Folder scanning skipped: ${folder.path}`, e);
    }
  }

  return songs;
}
