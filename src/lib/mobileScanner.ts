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
  
  return new Promise((resolve) => {
    const permissions = (window as any).cordova?.plugins?.permissions;
    if (!permissions) {
      console.warn('cordova-plugin-android-permissions is not available, falling back to Filesystem.requestPermissions');
      Filesystem.checkPermissions().then(status => {
        if (status.publicStorage === 'granted') {
          resolve(true);
        } else {
          Filesystem.requestPermissions().then(req => {
            resolve(req.publicStorage === 'granted');
          }).catch(() => resolve(false));
        }
      }).catch(() => resolve(false));
      return;
    }

    // List of permissions to request for maximum Android compatibility (Android 13+ and 12-)
    const permissionList = [
      permissions.READ_EXTERNAL_STORAGE,
      permissions.WRITE_EXTERNAL_STORAGE
    ];

    // Add READ_MEDIA_AUDIO for Android 13+ (API 33+) if defined
    if (permissions.READ_MEDIA_AUDIO) {
      permissionList.push(permissions.READ_MEDIA_AUDIO);
    } else {
      // Fallback string representation if not defined in older plugin versions
      permissionList.push('android.permission.READ_MEDIA_AUDIO');
    }

    permissions.requestPermissions(permissionList, (status: any) => {
      if (status && status.hasPermission) {
        resolve(true);
      } else {
        // Double check if at least one is granted
        permissions.hasPermission('android.permission.READ_MEDIA_AUDIO', (audioOk: any) => {
          if (audioOk && audioOk.hasPermission) {
            resolve(true);
          } else {
            permissions.hasPermission(permissions.READ_EXTERNAL_STORAGE, (storageOk: any) => {
              resolve(!!(storageOk && storageOk.hasPermission));
            });
          }
        });
      }
    }, () => {
      resolve(false);
    });
  });
}

interface MobileScanProgress {
  scannedCount: number;
  totalFiles: number;
  currentFileName: string;
}

// Recursively scans a directory path on mobile using Capacitor Filesystem with a depth limit
export async function scanMobileDirectory(
  directory: Directory,
  folderPath: string,
  maxDepth = 3,
  onProgress?: (progress: MobileScanProgress) => void
): Promise<LocalSong[]> {
  const songs: LocalSong[] = [];
  const filesToProcess: string[] = [];

  // Helper to recursively collect files with depth control
  async function collectFiles(path: string, depth = 0) {
    if (depth > maxDepth) return;
    try {
      const result = await Filesystem.readdir({
        path,
        directory
      });

      if (result && result.files) {
        for (const file of result.files) {
          const fullPath = path ? `${path}/${file.name}` : file.name;
          if (file.type === 'directory') {
            // Skip hidden directories, system folders, Android system, DCIM, Pictures, Movies, etc.
            if (
              !file.name.startsWith('.') && 
              !['Android', 'System Volume Information', 'LOST.DIR', 'DCIM', 'Pictures', 'Movies', 'Screenshots', 'Cache', 'cache', 'temp', 'Temp'].includes(file.name)
            ) {
              await collectFiles(fullPath, depth + 1);
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
      const fileResult = await Filesystem.getUri({ path: filePath, directory });
      const webUrl = (window as any).Capacitor.convertFileSrc(fileResult.uri);

      let parsedTitle = fileName.replace(/\.[^/.]+$/, "");
      let parsedArtist = 'Unknown Artist';
      let parsedAlbum = 'Unknown Album';
      let parsedCover: string | null = null;

      try {
        // Read only first 128KB of the file to parse metadata (super fast, prevents OOM crash)
        const fileChunk = await Filesystem.readFile({
          path: filePath,
          directory,
          length: 131072, // 128 KB
          offset: 0
        } as any);

        if (fileChunk && fileChunk.data) {
          const response = await fetch(`data:audio/mp3;base64,${fileChunk.data}`);
          const blob = await response.blob();
          const fileObject = new File([blob], fileName, { type: blob.type });
          
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
        duration: 180, // Default fallback
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
  
  // Standard folders to scan on mobile devices with customized depth limits
  const foldersToScan = [
    { dir: Directory.ExternalStorage, path: '', maxDepth: 1 }, // Scan root of /sdcard/ directly (non-recursive)
    { dir: Directory.ExternalStorage, path: 'Music', maxDepth: 3 }, // Scan Music folder up to 3 levels deep
    { dir: Directory.ExternalStorage, path: 'Download', maxDepth: 3 }, // Scan Download folder up to 3 levels deep
    { dir: Directory.ExternalStorage, path: 'Documents', maxDepth: 3 }, // Scan Documents folder up to 3 levels deep
    { dir: Directory.ExternalStorage, path: 'Ringtones', maxDepth: 2 },
    { dir: Directory.Documents, path: '', maxDepth: 3 }
  ];

  const songMap = new Map<string, LocalSong>();
  let totalCollectedFiles = 0;
  
  for (const folder of foldersToScan) {
    try {
      const results = await scanMobileDirectory(folder.dir, folder.path, folder.maxDepth, (progress) => {
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
