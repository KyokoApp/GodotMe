import { LocalSong, saveSong, getSongs } from './db';
import { Filesystem, Directory } from '@capacitor/filesystem';
import { Capacitor } from '@capacitor/core';

// Cloudinary config (read-only, no secret needed in frontend)
const CLOUDINARY_CLOUD_NAME = 'dtxpdx8ua';
export const CLOUDINARY_BASE_URL = `https://res.cloudinary.com/${CLOUDINARY_CLOUD_NAME}`;

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

// Fetch list of cloud songs from API (Cloudinary URLs stored in Supabase DB)
export async function fetchCloudMusicList(): Promise<any[]> {
  const res = await fetch('/api/cloud-songs');
  if (!res.ok) throw new Error('Gagal fetch daftar lagu cloud: ' + res.statusText);
  const data = await res.json();
  return data || [];
}

// Download a cloud song to device storage and save to IndexedDB
export async function downloadCloudSong(
  song: { id: string | number; title: string; artist?: string; album?: string; audio_url: string; cover_url?: string },
  onProgress?: (msg: string) => void
): Promise<LocalSong | null> {
  const fileName = `${song.title.replace(/[^a-z0-9]/gi, '_')}.mp3`;
  try {
    if (onProgress) onProgress(`Mengunduh ${song.title}...`);

    const audioUrl = song.audio_url;
    const localId = `cloud-dl-${song.id}`;

    if (Capacitor.isNativePlatform()) {
      // Download file as base64 on native
      await ensureMusicFolder();
      const response = await fetch(audioUrl);
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

      const localSong: LocalSong = {
        id: localId,
        title: song.title,
        artist: song.artist || 'Unknown Artist',
        album: song.album || 'KyokoBeat Cloud',
        duration: 0,
        cover: song.cover_url || null,
        fileHandle: null as any,
        path: `/storage/emulated/0/${filePath}`,
        fileSize: blob.size,
        addedAt: Date.now(),
        isCloud: false,
        isDownloaded: true,
        audioUrl: localUrl,
      };

      await saveSong(localSong);
      if (onProgress) onProgress(`✓ ${song.title} tersimpan!`);
      return localSong;
    } else {
      // Web fallback — save as offline with Cloudinary URL
      const localSong: LocalSong = {
        id: localId,
        title: song.title,
        artist: song.artist || 'Unknown Artist',
        album: song.album || 'KyokoBeat Cloud',
        duration: 0,
        cover: song.cover_url || null,
        fileHandle: null as any,
        path: audioUrl,
        fileSize: 0,
        addedAt: Date.now(),
        isCloud: false,
        isDownloaded: true,
        audioUrl: audioUrl,
      };
      await saveSong(localSong);
      if (onProgress) onProgress(`✓ ${song.title} disimpan ke offline!`);
      return localSong;
    }
  } catch (e: any) {
    console.error('Download failed:', e);
    if (onProgress) onProgress(`✗ Gagal download ${song.title}: ${e.message}`);
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
    f => !localIds.has(`cloud-dl-${f.id}`)
  );

  if (newFiles.length === 0) {
    if (onProgress) onProgress('Semua lagu sudah sinkron!');
    return 0;
  }

  if (onProgress) onProgress(`Ditemukan ${newFiles.length} lagu baru...`);

  let downloaded = 0;
  for (const file of newFiles) {
    const result = await downloadCloudSong(file, onProgress);
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
