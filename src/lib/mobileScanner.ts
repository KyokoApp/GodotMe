import { LocalSong } from './db';

// Helper to check if running inside a Capacitor Native App container
export function isCapacitorActive(): boolean {
  return typeof window !== 'undefined' && (window as any).Capacitor !== undefined;
}

// Check and request storage permissions on Android/iOS natively using our custom plugin
export async function requestMobileStoragePermission(): Promise<boolean> {
  if (!isCapacitorActive()) return false;
  try {
    const KyokoBeatNative = (window as any).Capacitor.Plugins.KyokoBeatNative;
    if (KyokoBeatNative) {
      const result = await KyokoBeatNative.checkAndRequestPermissions();
      return !!result.granted;
    }
  } catch (e) {
    console.error('Failed to request mobile storage permission via custom native plugin:', e);
  }
  return false;
}

interface MobileScanProgress {
  scannedCount: number;
  totalFiles: number;
  currentFileName: string;
}

// Scans all standard device storage locations on mobile (Android/iOS) using rapid native MediaStore queries
export async function scanAllMobileStorage(
  onProgress?: (progress: MobileScanProgress) => void
): Promise<LocalSong[]> {
  if (!isCapacitorActive()) return [];

  try {
    const KyokoBeatNative = (window as any).Capacitor.Plugins.KyokoBeatNative;
    if (!KyokoBeatNative) {
      console.warn('KyokoBeatNative plugin is not loaded, make sure you are running on native device');
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

    // Call the high-speed native MediaStore query!
    const result = await KyokoBeatNative.querySongs();
    
    if (result && result.songs) {
      const songsList: LocalSong[] = result.songs.map((song: any) => ({
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        cover: song.cover.startsWith('content://') ? null : song.cover, // Filter out content:// uri for web representation if needed or keep
        fileHandle: null as any,
        path: song.path,
        fileSize: song.fileSize,
        addedAt: song.addedAt,
        isCloud: false,
        audioUrl: song.audioUrl
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
