import { LocalSong } from './db';
import { extractMetadata } from './metadata';

// Check if browser supports File System Access API
export function isFileSystemAccessSupported(): boolean {
  return typeof window !== 'undefined' && 'showDirectoryPicker' in window;
}

// Verify permission on a handle
export async function verifyPermission(fileHandle: any, readWrite = false): Promise<boolean> {
  const options: any = {
    mode: readWrite ? 'readwrite' : 'read'
  };
  
  if ((await fileHandle.queryPermission(options)) === 'granted') {
    return true;
  }
  
  if ((await fileHandle.requestPermission(options)) === 'granted') {
    return true;
  }
  
  return false;
}

interface ScanProgress {
  scannedCount: number;
  totalFiles: number;
  currentFileName: string;
}

export async function scanDirectoryRecursive(
  dirHandle: any,
  onProgress?: (progress: ScanProgress) => void,
  path = ''
): Promise<LocalSong[]> {
  const songs: LocalSong[] = [];

  // First pass: collect all audio files to know the total count
  const audioFiles: { handle: any; relativePath: string }[] = [];
  
  async function collectFiles(directory: any, currentPath: string) {
    for await (const entry of (directory as any).values()) {
      if (entry.kind === 'file') {
        const ext = entry.name.split('.').pop()?.toLowerCase();
        if (ext && ['mp3', 'flac', 'wav', 'ogg', 'm4a'].includes(ext)) {
          audioFiles.push({
            handle: entry,
            relativePath: `${currentPath}${entry.name}`
          });
        }
      } else if (entry.kind === 'directory') {
        try {
          await collectFiles(entry, `${currentPath}${entry.name}/`);
        } catch (e) {
          console.warn(`Could not read subdirectory ${entry.name}:`, e);
        }
      }
    }
  }

  await collectFiles(dirHandle, path);

  const totalFiles = audioFiles.length;
  let scannedCount = 0;

  // Second pass: extract metadata for each file
  for (const item of audioFiles) {
    scannedCount++;
    if (onProgress) {
      onProgress({
        scannedCount,
        totalFiles,
        currentFileName: item.handle.name
      });
    }

    try {
      const file = await item.handle.getFile();
      const metadata = await extractMetadata(file);

      songs.push({
        id: item.relativePath, // Use relative path as unique ID
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        duration: metadata.duration,
        cover: metadata.cover,
        fileHandle: item.handle,
        path: item.relativePath,
        fileSize: file.size,
        addedAt: Date.now()
      });
    } catch (e) {
      console.error(`Failed to scan file ${item.handle.name}:`, e);
    }
  }

  return songs;
}

// Highly optimized background incremental sync
export async function syncFolderIncremental(
  dirHandle: any,
  existingSongs: LocalSong[],
  onProgress?: (progress: ScanProgress) => void
): Promise<{ added: LocalSong[]; deletedIds: string[] }> {
  // Collect files
  const audioFiles: { handle: any; relativePath: string }[] = [];
  
  async function collectFiles(directory: any, currentPath: string) {
    for await (const entry of (directory as any).values()) {
      if (entry.kind === 'file') {
        const ext = entry.name.split('.').pop()?.toLowerCase();
        if (ext && ['mp3', 'flac', 'wav', 'ogg', 'm4a'].includes(ext)) {
          audioFiles.push({
            handle: entry,
            relativePath: `${currentPath}${entry.name}`
          });
        }
      } else if (entry.kind === 'directory') {
        try {
          await collectFiles(entry, `${currentPath}${entry.name}/`);
        } catch (e) {
          console.warn(`Could not read subdirectory ${entry.name}:`, e);
        }
      }
    }
  }

  await collectFiles(dirHandle, '');

  const existingMap = new Map<string, LocalSong>();
  existingSongs.forEach(s => existingMap.set(s.id, s));

  const currentPaths = new Set(audioFiles.map(f => f.relativePath));
  
  // Find deleted songs (exist in DB but not in directory)
  const deletedIds: string[] = [];
  existingSongs.forEach(s => {
    if (!s.isCloud && !currentPaths.has(s.id)) {
      deletedIds.push(s.id);
    }
  });

  // Find new songs or changed files (by path/size)
  const filesToScan: { handle: any; relativePath: string }[] = [];
  for (const file of audioFiles) {
    const existing = existingMap.get(file.relativePath);
    if (!existing) {
      // New file completely
      filesToScan.push(file);
    } else {
      // Check if file size changed (could mean file replaced)
      try {
        const fInfo = await file.handle.getFile();
        if (fInfo.size !== existing.fileSize) {
          filesToScan.push(file);
        }
      } catch (e) {
        console.warn(`Failed to inspect file size for ${file.relativePath}`, e);
      }
    }
  }

  const added: LocalSong[] = [];
  const totalFiles = filesToScan.length;
  let scannedCount = 0;

  // Scan only new/changed files (super fast!)
  for (const item of filesToScan) {
    scannedCount++;
    if (onProgress) {
      onProgress({
        scannedCount,
        totalFiles,
        currentFileName: item.handle.name
      });
    }

    try {
      const file = await item.handle.getFile();
      const metadata = await extractMetadata(file);

      added.push({
        id: item.relativePath,
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        duration: metadata.duration,
        cover: metadata.cover,
        fileHandle: item.handle,
        path: item.relativePath,
        fileSize: file.size,
        addedAt: Date.now()
      });
    } catch (e) {
      console.error(`Failed to sync file ${item.handle.name}:`, e);
    }
  }

  return { added, deletedIds };
}
