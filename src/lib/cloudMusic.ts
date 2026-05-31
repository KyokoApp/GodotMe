import supabase from './supabase';
import { LocalSong, saveSong, getSongs, deleteSong } from './db';
import { Filesystem, Directory } from '@capacitor/filesystem';
import { Capacitor } from '@capacitor/core';

const BUCKET = 'kyokobeat-music';
const MUSIC_FOLDER = 'Android/media/com.kyokobeat.musicplayer/Music';

// Ensure music folder exists on device
export async function ensureMusicFolder(): Promise<void> {
  if (!Capacitor.isNativePlatform()) return;
  try {
    await Filesystem.mkdir({
      path: MUSIC_FOLDER,
      directory: Directory.ExternalStorage,
      recursive: true,
    });
  } catch (e) {
    // Folder already exists, ignore
  }
}

// Fetch list of songs uploaded via WA bot from Supabase Storage
export async function fetchCloudMusicList(): Promise<any[]> {
  const { data, error } = await supabase.storage.from(BUCKET).list('songs', {
    sortBy: { column: 'created_at', order: 'desc' },
  });
  if (error) throw new Error('Gagal fetch daftar lagu cloud: ' + error.message);
  return data || [];
}

// Download a cloud song to device storage and save to IndexedDB
export async function downloadCloudSong(
  fileName: string,
  onProgress?: (msg: string) => void
): Promise<LocalSong | null> {
  try {
    if (onProgress) onProgress(`Mengunduh ${fileName}...`);

    // Get public URL
    const { data: urlData } = supabase.storage.from(BUCKET).getPublicUrl(`songs/${fileName}`);
    const publicUrl = urlData.publicUrl;

    if (Capacitor.isNativePlatform()) {
      // Download file as base64 on native
      await ensureMusicFolder();
      const response = await fetch(publicUrl);
      const blob = await response.blob();
      const base64 = await blobToBase64(blob);

      const filePath = `${MUSIC_FOLDER}/${fileName}`;
      await Filesystem.writeFile({
        path: filePath,
        data: base64,
        directory: Directory.ExternalStorage,
        recursive: true,
      });

      const localUrl = Capacitor.convertFileSrc(
        `/storage/emulated/0/${filePath}`
      );

      const song: LocalSong = {
        id: `cloud-dl-${fileName}`,
        title: fileName.replace(/\.[^/.]+$/, '').replace(/_/g, ' '),
        artist: 'Unknown Artist',
        album: 'KyokoBeat Cloud',
        duration: 0,
        cover: null,
        fileHandle: null as any,
        path: `/storage/emulated/0/${filePath}`,
        fileSize: blob.size,
        addedAt: Date.now(),
        isCloud: false,
        audioUrl: localUrl,
      };

      await saveSong(song);
      if (onProgress) onProgress(`✓ ${fileName} tersimpan!`);
      return song;
    } else {
      // Web fallback — stream directly
      const song: LocalSong = {
        id: `cloud-dl-${fileName}`,
        title: fileName.replace(/\.[^/.]+$/, '').replace(/_/g, ' '),
        artist: 'Unknown Artist',
        album: 'KyokoBeat Cloud',
        duration: 0,
        cover: null,
        fileHandle: null as any,
        path: publicUrl,
        fileSize: 0,
        addedAt: Date.now(),
        isCloud: false,
        audioUrl: publicUrl,
      };
      await saveSong(song);
      return song;
    }
  } catch (e: any) {
    console.error('Download failed:', e);
    if (onProgress) onProgress(`✗ Gagal download ${fileName}: ${e.message}`);
    return null;
  }
}

// Download all new cloud songs not yet in local library
export async function syncAllCloudMusic(
  onProgress?: (msg: string) => void
): Promise<number> {
  if (onProgress) onProgress('Memeriksa lagu baru di cloud...');

  const [cloudFiles, localSongs] = await Promise.all([
    fetchCloudMusicList(),
    getSongs(),
  ]);

  const localIds = new Set(localSongs.map(s => s.id));
  const newFiles = cloudFiles.filter(
    f => !localIds.has(`cloud-dl-${f.name}`)
  );

  if (newFiles.length === 0) {
    if (onProgress) onProgress('Semua lagu sudah sinkron!');
    return 0;
  }

  if (onProgress) onProgress(`Ditemukan ${newFiles.length} lagu baru...`);

  let downloaded = 0;
  for (const file of newFiles) {
    const result = await downloadCloudSong(file.name, onProgress);
    if (result) downloaded++;
  }

  return downloaded;
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const result = reader.result as string;
      resolve(result.split(',')[1]);
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}
