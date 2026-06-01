export interface LocalSong {
  id: string; // unique identifier, e.g. relative path or path-hash
  title: string;
  artist: string;
  album: string;
  duration: number; // in seconds
  cover: string | null; // base64 or null
  fileHandle: FileSystemFileHandle;
  path: string;
  fileSize: number;
  addedAt: number;
  isCloud?: boolean; // true = streaming dari cloud (online tab)
  isDownloaded?: boolean; // true = lagu cloud yang sudah didownload ke device (muncul di offline juga)
  audioUrl?: string; // for cloud songs
}

export interface LocalPlaylist {
  id: string;
  name: string;
  description: string;
  songIds: string[];
  createdAt: number;
}

const DB_NAME = 'kyokobeat-db';
const DB_VERSION = 2; // v2: added hidden_songs store

export function initDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => {
      console.error('Failed to open IndexedDB');
      reject(request.error);
    };

    request.onsuccess = () => {
      resolve(request.result);
    };

    request.onupgradeneeded = (event) => {
      const db = request.result;
      
      // Store songs
      if (!db.objectStoreNames.contains('songs')) {
        db.createObjectStore('songs', { keyPath: 'id' });
      }

      // Store settings (like root directory handle)
      if (!db.objectStoreNames.contains('settings')) {
        db.createObjectStore('settings', { keyPath: 'key' });
      }

      // Store local playlists
      if (!db.objectStoreNames.contains('playlists')) {
        db.createObjectStore('playlists', { keyPath: 'id' });
      }

      // Store local favorites
      if (!db.objectStoreNames.contains('favorites')) {
        db.createObjectStore('favorites', { keyPath: 'songId' });
      }

      // Store hidden/blacklisted songs (won't be re-added by scanner)
      if (!db.objectStoreNames.contains('hidden_songs')) {
        db.createObjectStore('hidden_songs', { keyPath: 'songId' });
      }
    };
  });
}

// Helper to run a transaction
async function getStore(storeName: string, mode: IDBTransactionMode = 'readonly') {
  const db = await initDB();
  const tx = db.transaction(storeName, mode);
  return tx.objectStore(storeName);
}

export async function getSongs(): Promise<LocalSong[]> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('songs', 'readonly');
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function saveSongs(songs: LocalSong[]): Promise<void> {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('songs', 'readwrite');
    const store = tx.objectStore('songs');

    songs.forEach(song => {
      store.put(song);
    });

    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function saveSong(song: LocalSong): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('songs', 'readwrite');
      const request = store.put(song);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function deleteSong(id: string): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('songs', 'readwrite');
      const request = store.delete(id);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function clearSongs(): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('songs', 'readwrite');
      const request = store.clear();
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function getSetting(key: string): Promise<any> {
  return new Promise(async (resolve) => {
    try {
      const store = await getStore('settings', 'readonly');
      const request = store.get(key);
      request.onsuccess = () => resolve(request.result?.value || null);
      request.onerror = () => resolve(null);
    } catch (e) {
      resolve(null);
    }
  });
}

export async function saveSetting(key: string, value: any): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('settings', 'readwrite');
      const request = store.put({ key, value });
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function getPlaylists(): Promise<LocalPlaylist[]> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('playlists', 'readonly');
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function savePlaylist(playlist: LocalPlaylist): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('playlists', 'readwrite');
      const request = store.put(playlist);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function deletePlaylist(id: string): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('playlists', 'readwrite');
      const request = store.delete(id);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function getFavorites(): Promise<string[]> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('favorites', 'readonly');
      const request = store.getAll();
      request.onsuccess = () => {
        const list = request.result || [];
        resolve(list.map(f => f.songId));
      };
      request.onerror = () => reject(request.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function isFavorite(songId: string): Promise<boolean> {
  return new Promise(async (resolve) => {
    try {
      const store = await getStore('favorites', 'readonly');
      const request = store.get(songId);
      request.onsuccess = () => resolve(!!request.result);
      request.onerror = () => resolve(false);
    } catch (e) {
      resolve(false);
    }
  });
}

export async function toggleFavorite(songId: string): Promise<boolean> {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('favorites', 'readwrite');
    const store = tx.objectStore('favorites');
    const getReq = store.get(songId);

    getReq.onsuccess = () => {
      if (getReq.result) {
        store.delete(songId);
        tx.oncomplete = () => resolve(false); // No longer favorite
      } else {
        store.put({ songId, addedAt: Date.now() });
        tx.oncomplete = () => resolve(true); // Is favorite
      }
    };

    getReq.onerror = () => reject(getReq.error);
    tx.onerror = () => reject(tx.error);
  });
}

// ── Hidden Songs Blacklist ──────────────────────────────────────────────────
// Menyimpan path/ID lagu yang sengaja disembunyikan dari library.
// Scan tidak akan re-add lagu yang ada di blacklist ini.

export interface HiddenSong {
  songId: string;   // same as LocalSong.id / scan path
  path: string;     // file path (untuk matching di scanner)
  hiddenAt: number;
}

export async function addHiddenSong(songId: string, path: string): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('hidden_songs', 'readwrite');
      const request = store.put({ songId, path, hiddenAt: Date.now() });
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) { reject(e); }
  });
}

export async function removeHiddenSong(songId: string): Promise<void> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('hidden_songs', 'readwrite');
      const request = store.delete(songId);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    } catch (e) { reject(e); }
  });
}

export async function getHiddenSongs(): Promise<HiddenSong[]> {
  return new Promise(async (resolve, reject) => {
    try {
      const store = await getStore('hidden_songs', 'readonly');
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    } catch (e) { reject(e); }
  });
}

// Returns Set of hidden paths for fast O(1) lookup during scan
export async function getHiddenPathSet(): Promise<Set<string>> {
  const hidden = await getHiddenSongs();
  const set = new Set<string>();
  hidden.forEach(h => {
    set.add(h.songId);
    set.add(h.path);
  });
  return set;
}
