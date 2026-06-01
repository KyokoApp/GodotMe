import { LocalSong, getHiddenPathSet } from './db';
import { Capacitor } from '@capacitor/core';

// Helper to check if running inside a Capacitor Native App container
export function isCapacitorActive(): boolean {
  return typeof window !== 'undefined' && (window as any).Capacitor !== undefined && (window as any).Capacitor.isNativePlatform();
}

// Check and request storage permissions via KyokoBeatNative plugin
export async function requestMobileStoragePermission(): Promise<boolean> {
  if (!isCapacitorActive()) return false;
  try {
    const KyokoBeatNative = (window as any).Capacitor.Plugins.KyokoBeatNative;
    if (KyokoBeatNative) {
      const result = await KyokoBeatNative.checkAndRequestPermissions();
      return !!result.granted;
    }
  } catch (e) {
    console.error('Failed to request mobile storage permission:', e);
  }
  return false;
}

interface MobileScanProgress {
  scannedCount: number;
  totalFiles: number;
  currentFileName: string;
}

// Scans all device storage using native MediaStore via KyokoBeatNative plugin
export async function scanAllMobileStorage(
  onProgress?: (progress: MobileScanProgress) => void
): Promise<LocalSong[]> {
  if (!isCapacitorActive()) return [];

  try {
    const KyokoBeatNative = (window as any).Capacitor.Plugins.KyokoBeatNative;
    if (!KyokoBeatNative) {
      console.warn('KyokoBeatNative plugin not loaded');
      return [];
    }

    // Request permissions first
    const permResult = await KyokoBeatNative.checkAndRequestPermissions();
    if (!permResult.granted) {
      console.warn('Storage permission denied by user');
      return [];
    }

    if (onProgress) {
      onProgress({
        scannedCount: 0,
        totalFiles: 100,
        currentFileName: 'Menghubungkan ke database musik Android...'
      });
    }

    const result = await KyokoBeatNative.querySongs();

    if (result && result.songs) {
      const hiddenPaths = await getHiddenPathSet();
      const songsList: LocalSong[] = result.songs
        .filter((song: any) => !hiddenPaths.has(song.id) && !hiddenPaths.has(song.path))
        .map((song: any) => ({
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: song.duration,
          cover: song.cover,
          fileHandle: null as any,
          path: song.path,
          fileSize: song.fileSize,
          addedAt: song.addedAt,
          isCloud: false,
          // Convert native file path to Capacitor-accessible URL for audio playback
          audioUrl: song.audioUrl
            ? song.audioUrl
            : song.path
              ? Capacitor.convertFileSrc(song.path)
              : undefined
        }));

      if (onProgress) {
        onProgress({
          scannedCount: songsList.length,
          totalFiles: songsList.length,
          currentFileName: `Selesai! Berhasil mendeteksi ${songsList.length} lagu.`
        });
      }

      return songsList;
    }
  } catch (e) {
    console.error('Failed to scan mobile storage natively:', e);
  }

  return [];
}
