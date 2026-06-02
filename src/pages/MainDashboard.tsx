import React, { useState, useEffect, useRef } from 'react';
import {
  Search,
  FolderSync,
  Music,
  FolderHeart,
  Heart,
  Play,
  Pause,
  SkipForward,
  SkipBack,
  Shuffle,
  Repeat,
  Volume2,
  VolumeX,
  Plus,
  Trash2,
  FolderOpen,
  Cloud,
  Laptop,
  CheckCircle,
  Loader2,
  SlidersHorizontal,
  LayoutGrid,
  List,
  Disc,
  ArrowUpDown,
  AlertTriangle,
  HelpCircle,
  X,
  RefreshCw,
  EyeOff,
  Youtube,
  ChevronDown,
} from 'lucide-react';
import audioManager from '../lib/audio';
import {
  LocalSong,
  LocalPlaylist,
  getSongs,
  saveSongs,
  clearSongs,
  getPlaylists,
  savePlaylist,
  deletePlaylist,
  getFavorites,
  toggleFavorite,
  getSetting,
  saveSetting,
  deleteSong,
  addHiddenSong,
} from '../lib/db';
import { scanDirectoryRecursive, verifyPermission, syncFolderIncremental } from '../lib/scanner';
import { isCapacitorActive, requestMobileStoragePermission, scanAllMobileStorage } from '../lib/mobileScanner';
import { checkForUpdate } from '../lib/updater';
import UpdateDialog from '../components/UpdateDialog';
import { ensureMusicFolder, downloadCloudSong } from '../lib/cloudMusic';
import SongCard from '../components/SongCard';
import WaveformVisualizer from '../components/WaveformVisualizer';
import CloudSyncIndicator from '../components/CloudSyncIndicator';
import AuthModal from '../components/AuthModal';
import PlaylistModal from '../components/PlaylistModal';
import RenameModal from '../components/RenameModal';
import DeleteConfirmModal from '../components/DeleteConfirmModal';
import YtDownloadModal from '../components/YtDownloadModal';
import { useToast } from '../components/Toast';
import supabase from '../lib/supabase';

export default function MainDashboard() {
  // App states
  const [localSongs, setLocalSongs] = useState<LocalSong[]>([]);
  const [cloudSongs, setCloudSongs] = useState<LocalSong[]>([]);
  const [allSongs, setAllSongs] = useState<LocalSong[]>([]);
  const [playlists, setPlaylists] = useState<LocalPlaylist[]>([]);
  const [favorites, setFavorites] = useState<string[]>([]);
  
  // Tab & Filter states
  const [activeTab, setActiveTab] = useState<'library' | 'playlists' | 'favorites'>('library');
  const [sourceFilter, setSourceFilter] = useState<'all' | 'online' | 'offline'>('offline');
  const [selectedPlaylistId, setSelectedPlaylistId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'title' | 'artist' | 'album'>('title');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

  // Player states (synced from audioManager)
  const [playerState, setPlayerState] = useState({
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    volume: 1,
    currentSong: null as LocalSong | null,
    isMuted: false,
  });

  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState<'none' | 'one' | 'all'>('none');
  const [playerVisible, setPlayerVisible] = useState(true);
  const [showFullPlayer, setShowFullPlayer] = useState(false);

  // Update checker
  const [updateInfo, setUpdateInfo] = useState<any>(null);
  const [showUpdateDialog, setShowUpdateDialog] = useState(false);

  // Scanning / Syncing states
  const [scanning, setScanning] = useState(false);
  const [syncingBackground, setSyncingBackground] = useState(false);
  const [scanProgress, setScanProgress] = useState({
    scannedCount: 0,
    totalFiles: 0,
    currentFileName: ''
  });

  // Local folder permissions states
  const [needPermission, setNeedPermission] = useState(false);
  const [showHelp, setShowHelp] = useState(false);

  // Modal states
  const [isAuthOpen, setIsAuthOpen] = useState(false);
  const [isPlaylistOpen, setIsPlaylistOpen] = useState(false);
  const [isRenameOpen, setIsRenameOpen] = useState(false);
  const [songToAddToPlaylist, setSongToAddToPlaylist] = useState<LocalSong | null>(null);
  const [songToRename, setSongToRename] = useState<LocalSong | null>(null);
  const [isDeleteOpen, setIsDeleteOpen] = useState(false);
  const [songToDelete, setSongToDelete] = useState<LocalSong | null>(null);
  const [isDeleteAllOpen, setIsDeleteAllOpen] = useState<false | 'choose' | 'hide' | 'delete'>(false);
  const [durationFilter, setDurationFilter] = useState<'all' | 'under1' | '1to2' | 'over2'>('over2');
  const [syncingCloud, setSyncingCloud] = useState(false);
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [showCreatePlaylistRow, setShowCreatePlaylistRow] = useState(false);

  const [downloadedCloudIds, setDownloadedCloudIds] = useState<Set<string>>(new Set());

  // YouTube Download modal state
  const [isYtModalOpen, setIsYtModalOpen] = useState(false);

  // Auth state
  const [user, setUser] = useState<any>(null);

  const { toast } = useToast();

  // 1. Initial Load & Auth Sync
  useEffect(() => {
    // Listen for auth state changes
    supabase.auth.getSession().then(({ data: { session } }: any) => {
      setUser(session?.user ?? null);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event: any, session: any) => {
      setUser(session?.user ?? null);
    });

    // Load local songs, playlists, favorites
    loadLocalDataAndSync();
    // Load pre-seeded cloud songs
    loadCloudSongs();

    // Cek update di Android
    if (isCapacitorActive()) {
      checkForUpdate().then((info) => {
        if (info) setUpdateInfo(info);
      });
    }

    return () => subscription.unsubscribe();
  }, []);

  // 2. Sync Audio Manager State
  useEffect(() => {
    const unsubscribe = audioManager.subscribe((state) => {
      setPlayerState(prev => {
        // Kalau lagu baru mulai, tampilkan player lagi
        if (state.currentSong && state.currentSong.id !== prev.currentSong?.id) {
          setPlayerVisible(true);
        }
        return state;
      });
    });

    // Handle track ended
    audioManager.onTrackEnded = () => {
      handleTrackEnded();
    };

    return () => {
      unsubscribe();
    };
  }, [playerState.currentSong, shuffle, repeat, allSongs, activeTab, selectedPlaylistId]);

  // Check directory permission status
  const checkDirectoryPermission = async () => {
    if (isCapacitorActive()) return; // Capacitor handles permissions via custom native prompt
    try {
      const dirHandle = await getSetting('rootDirectoryHandle');
      if (dirHandle) {
        const status = await dirHandle.queryPermission({ mode: 'read' });
        if (status !== 'granted') {
          setNeedPermission(true);
        } else {
          setNeedPermission(false);
        }
      }
    } catch (e) {
      console.warn('Error checking directory permission:', e);
    }
  };

  // Run directory permission check when local songs exist
  useEffect(() => {
    if (localSongs.length > 0) {
      checkDirectoryPermission();
    }
  }, [localSongs]);

  // Request/Restore folder permissions
  const handleGrantPermission = async () => {
    try {
      const dirHandle = await getSetting('rootDirectoryHandle');
      if (dirHandle) {
        const status = await dirHandle.requestPermission({ mode: 'read' });
        if (status === 'granted') {
          setNeedPermission(false);
          toast('Izin folder musik lokal berhasil diaktifkan kembali!', 'success');
          await loadLocalDataAndSync();
        } else {
          toast('Izin folder ditolak.', 'error');
        }
      }
    } catch (e) {
      console.error(e);
      toast('Gagal mengaktifkan kembali izin folder. Silakan klik "Rescan Folder".', 'error');
    }
  };

  // Load local IndexedDB data and perform automatic background incremental sync
  const loadLocalDataAndSync = async () => {
    try {
      const songs = await getSongs();
      const pls = await getPlaylists();
      const favs = await getFavorites();
      
      setLocalSongs(songs);
      setPlaylists(pls);
      setFavorites(favs);

      // Perform automatic background incremental sync if folder permission is already granted
      if (isCapacitorActive()) {
        const permitted = await requestMobileStoragePermission();
        if (permitted) {
          runBackgroundSyncMobile(songs);
        }
      } else {
        const dirHandle = await getSetting('rootDirectoryHandle');
        if (dirHandle) {
          const permitted = await dirHandle.queryPermission({ mode: 'read' });
          if (permitted === 'granted') {
            runBackgroundSync(dirHandle, songs);
          }
        }
      }
    } catch (e) {
      console.error('Failed to load local IndexedDB data:', e);
    }
  };

  // Run background sync for Mobile (Capacitor)
  const runBackgroundSyncMobile = async (currentSongs: LocalSong[]) => {
    setSyncingBackground(true);
    try {
      // Step 1: Scan local files from device
      const songs = await scanAllMobileStorage();

      // Step 2: Fetch current cloud song list to remove stale downloaded entries
      let validCloudIds = new Set<string>();
      try {
        const res = await fetch('/api/cloud-songs');
        if (res.ok) {
          const cloudData = await res.json();
          cloudData.forEach((s: any) => validCloudIds.add(`cloud-dl-${s.id}`));
        }
      } catch (e) {
        console.warn('Could not fetch cloud list during bg sync:', e);
      }

      // Step 3: Get existing downloaded cloud songs from DB
      const existingDownloaded = currentSongs.filter(s => s.isDownloaded);
      // Remove downloaded cloud songs that no longer exist in the cloud API
      for (const dl of existingDownloaded) {
        if (!validCloudIds.has(dl.id)) {
          await deleteSong(dl.id);
          console.log(`[Auto-Sync Mobile] Removed stale downloaded cloud song: ${dl.title}`);
        }
      }

      // Step 4: Merge: keep valid downloaded songs + fresh local scan
      const validDownloaded = existingDownloaded.filter(s => validCloudIds.has(s.id));
      const allSongsToSave = [...songs, ...validDownloaded];

      if (allSongsToSave.length !== currentSongs.length) {
        await clearSongs();
        await saveSongs(allSongsToSave);
        setLocalSongs(allSongsToSave);
        console.log(`[Auto-Sync Mobile] Updated library with ${allSongsToSave.length} songs.`);
      }
    } catch (e) {
      console.warn('Background mobile sync failed:', e);
    } finally {
      setSyncingBackground(false);
    }
  };

  // Run background sync for Desktop (Web)
  const runBackgroundSync = async (dirHandle: any, currentSongs: LocalSong[]) => {
    setSyncingBackground(true);
    try {
      const { added, deletedIds } = await syncFolderIncremental(dirHandle, currentSongs);
      
      let changed = false;

      // Delete missing songs
      if (deletedIds.length > 0) {
        changed = true;
        for (const id of deletedIds) {
          await deleteSong(id);
        }
        console.log(`[Auto-Sync] Deleted ${deletedIds.length} missing songs.`);
      }

      // Add new songs
      if (added.length > 0) {
        changed = true;
        await saveSongs(added);
        console.log(`[Auto-Sync] Added ${added.length} newly detected songs.`);
        toast(`Berhasil mendeteksi ${added.length} lagu baru di folder secara otomatis!`, 'success');
      }

      if (changed) {
        const songs = await getSongs();
        setLocalSongs(songs);
      }
    } catch (e) {
      console.warn('Background sync failed:', e);
    } finally {
      setSyncingBackground(false);
    }
  };

  // Load cloud songs from Vercel API — always show all cloud songs even if downloaded
  const loadCloudSongs = async () => {
    try {
      const res = await fetch('/api/cloud-songs');
      if (res.ok) {
        const data = await res.json();

        // Build set of valid cloud IDs from API
        const validCloudDlIds = new Set<string>(data.map((s: any) => `cloud-dl-${s.id}`));

        // Get all local songs from DB
        const localSongsFromDB = await getSongs();

        // Remove downloaded cloud songs that no longer exist in the API (deleted from Supabase/Cloudinary)
        const staleDownloaded = localSongsFromDB.filter(s => s.isDownloaded && !validCloudDlIds.has(s.id));
        for (const stale of staleDownloaded) {
          await deleteSong(stale.id);
          console.log(`[Cloud Refresh] Removed stale downloaded song: ${stale.title}`);
        }

        // Update local songs state if any were removed
        if (staleDownloaded.length > 0) {
          const freshLocal = await getSongs();
          setLocalSongs(freshLocal.filter(s => !s.isCloud));
          toast(`🗑️ ${staleDownloaded.length} lagu yang sudah dihapus dari cloud ikut dibersihkan.`, 'info');
        }

        // Track which cloud songs have been downloaded (for UI indicator)
        const freshDb = staleDownloaded.length > 0 ? await getSongs() : localSongsFromDB;
        const dlIds = new Set(freshDb.filter(s => s.isDownloaded).map(s => s.id));
        setDownloadedCloudIds(dlIds);

        const formattedCloudSongs: LocalSong[] = data.map((song: any) => ({
          id: `cloud-${song.id}`,
          title: song.title,
          artist: song.artist || 'Unknown Artist',
          album: song.album || 'Unknown Album',
          duration: song.duration || 0,
          cover: song.cover_url || null,
          fileHandle: null as any,
          path: song.audio_url,
          fileSize: 0,
          addedAt: Date.now(),
          isCloud: true,
          isDownloaded: false,
          audioUrl: song.audio_url,
        }));
        setCloudSongs(formattedCloudSongs);
      }
    } catch (e) {
      console.warn('Failed to load cloud songs:', e);
    }
  };

  // Combine local and cloud songs (cloud streaming + local/downloaded)
  useEffect(() => {
    setAllSongs([...cloudSongs, ...localSongs]);
  }, [localSongs, cloudSongs]);

  // Get active queue for playing next/prev
  const getActiveQueue = (): LocalSong[] => {
    let list: LocalSong[] = [];
    if (activeTab === 'library') {
      list = getFilteredSongs();
    } else if (activeTab === 'favorites') {
      list = allSongs.filter(s => favorites.includes(songIdOf(s)));
    } else if (activeTab === 'playlists' && selectedPlaylistId) {
      const pl = playlists.find(p => p.id === selectedPlaylistId);
      if (pl) {
        list = allSongs.filter(s => pl.songIds.includes(songIdOf(s)));
      }
    }
    return list.length > 0 ? list : allSongs;
  };

  const songIdOf = (song: LocalSong) => song.id;

  // Handle track ended
  const handleTrackEnded = () => {
    if (repeat === 'one') {
      audioManager.seek(0);
      audioManager.togglePlay(); // resume
      return;
    }

    playNextTrack();
  };

  const playNextTrack = () => {
    const queue = getActiveQueue();
    if (queue.length === 0) return;

    const currentSong = playerState.currentSong;
    let nextIndex = 0;

    if (shuffle) {
      nextIndex = Math.floor(Math.random() * queue.length);
    } else if (currentSong) {
      const currentIndex = queue.findIndex(s => songIdOf(s) === songIdOf(currentSong));
      if (currentIndex !== -1) {
        nextIndex = currentIndex + 1;
        if (nextIndex >= queue.length) {
          nextIndex = repeat === 'all' ? 0 : -1;
        }
      }
    }

    if (nextIndex !== -1 && queue[nextIndex]) {
      handlePlaySong(queue[nextIndex]);
    }
  };

  const playPrevTrack = () => {
    const queue = getActiveQueue();
    if (queue.length === 0) return;

    const currentSong = playerState.currentSong;
    let prevIndex = 0;

    if (shuffle) {
      prevIndex = Math.floor(Math.random() * queue.length);
    } else if (currentSong) {
      const currentIndex = queue.findIndex(s => songIdOf(s) === songIdOf(currentSong));
      if (currentIndex !== -1) {
        prevIndex = currentIndex - 1;
        if (prevIndex < 0) {
          prevIndex = repeat === 'all' ? queue.length - 1 : 0;
        }
      }
    }

    if (queue[prevIndex]) {
      handlePlaySong(queue[prevIndex]);
    }
  };

  // Play song wrapper with automatic permission request
  const handlePlaySong = async (song: LocalSong) => {
    if (!song.isCloud) {
      try {
        if (isCapacitorActive()) {
          const permitted = await requestMobileStoragePermission();
          if (!permitted) {
            toast('Mohon berikan izin penyimpanan untuk memutar lagu lokal Anda.', 'info');
            return;
          }
        } else {
          const dirHandle = await getSetting('rootDirectoryHandle');
          if (dirHandle) {
            const permitted = await verifyPermission(dirHandle, false);
            if (!permitted) {
              toast('Mohon berikan izin folder musik untuk memutar lagu lokal Anda.', 'info');
              setNeedPermission(true);
              return;
            }
          }
        }
      } catch (e) {
        console.warn('Could not verify directory handle permission:', e);
      }
    }

    try {
      await audioManager.playSong(song);
    } catch (err: any) {
      console.error(err);
      if (!song.isCloud) {
        toast('Gagal memutar lagu lokal. Klik banner kuning di atas untuk mengaktifkan izin folder kembali.', 'error');
        if (!isCapacitorActive()) setNeedPermission(true);
      } else {
        toast('Gagal memutar lagu cloud: ' + err.message, 'error');
      }
    }
  };

  // Scan folder manual trigger (performs full scan)
  const handleRescan = async () => {
    if (isCapacitorActive()) {
      setScanning(true);
      toast('Memulai pemindaian penyimpanan HP Anda...', 'info');
      try {
        const permitted = await requestMobileStoragePermission();
        if (!permitted) {
          toast('Izin penyimpanan ditolak.', 'error');
          setScanning(false);
          return;
        }
        const songs = await scanAllMobileStorage((progress) => {
          setScanProgress(progress);
        });
        await clearSongs();
        await saveSongs(songs);
        setLocalSongs(songs);
        toast(`Berhasil mendeteksi ${songs.length} lagu baru dari HP Anda!`, 'success');
      } catch (e: any) {
        toast('Gagal memindai HP: ' + e.message, 'error');
      } finally {
        setScanning(false);
      }
      return;
    }

    try {
      if (!('showDirectoryPicker' in window)) {
        toast('Browser Anda tidak mendukung scanning folder lokal', 'error');
        return;
      }

      const dirHandle = await (window as any).showDirectoryPicker();
      setScanning(true);
      toast('Memulai scanning folder musik...', 'info');

      // Save directory handle to settings
      await saveSetting('rootDirectoryHandle', dirHandle);

      // Verify permission
      const permitted = await verifyPermission(dirHandle, false);
      if (!permitted) {
        setScanning(false);
        toast('Izin akses folder ditolak', 'error');
        return;
      }

      // Scan recursively
      const songs = await scanDirectoryRecursive(dirHandle, (progress) => {
        setScanProgress(progress);
      });

      if (songs.length > 0) {
        await clearSongs();
        await saveSongs(songs);
        await loadLocalDataAndSync();
        setNeedPermission(false);
        toast(`Berhasil mendeteksi ${songs.length} lagu baru!`, 'success');
      } else {
        toast('Tidak ada file audio (.mp3, .wav, .flac, .ogg, .m4a) yang terdeteksi', 'info');
      }
    } catch (err: any) {
      console.error(err);
      if (err.name !== 'AbortError') {
        toast('Gagal melakukan scan folder: ' + err.message, 'error');
      }
    } finally {
      setScanning(false);
    }
  };

  // Toggle favorite song
  const handleToggleFav = async (song: LocalSong) => {
    const isFav = await toggleFavorite(song.id);
    setFavorites(prev => {
      if (isFav) {
        return [...prev, song.id];
      } else {
        return prev.filter(id => id !== song.id);
      }
    });

    toast(isFav ? 'Ditambahkan ke Favorit' : 'Dihapus dari Favorit', 'success');
  };

  // Delete local song from database
  const handleDeleteSong = (song: LocalSong) => {
    setSongToDelete(song);
    setIsDeleteOpen(true);
  };

  // Helper: hapus song dari state dan DB, tanpa trigger rescan
  const removeSongFromState = async (song: LocalSong) => {
    await deleteSong(song.id);

    // Remove from favorites
    if (favorites.includes(song.id)) {
      await toggleFavorite(song.id);
      setFavorites(prev => prev.filter(id => id !== song.id));
    }

    // Remove from playlists
    for (const pl of playlists) {
      if (pl.songIds.includes(song.id)) {
        const updatedPl = { ...pl, songIds: pl.songIds.filter(id => id !== song.id) };
        await savePlaylist(updatedPl);
      }
    }

    // Update UI state
    setLocalSongs(prev => prev.filter(s => s.id !== song.id));

    // Stop if currently playing
    if (playerState.currentSong?.id === song.id) {
      audioManager.seek(0);
      if (playerState.isPlaying) audioManager.togglePlay();
    }
  };

  // Sembunyikan lagu dari library (file tetap di HP, tapi tidak akan muncul lagi saat scan)
  const handleHideSong = async () => {
    const song = songToDelete;
    if (!song) return;
    setIsDeleteOpen(false);
    setSongToDelete(null);
    try {
      await addHiddenSong(song.id, song.path);
      await removeSongFromState(song);
      toast(`"${song.title}" disembunyikan dari library. Tidak akan muncul lagi meski di-rescan.`, 'success');
    } catch (e: any) {
      toast('Gagal menyembunyikan lagu: ' + e.message, 'error');
    }
  };

  // Hapus file fisik dari HP (Capacitor) + sembunyikan dari library
  const handleDeleteFileSong = async () => {
    const song = songToDelete;
    if (!song) return;
    setIsDeleteOpen(false);
    setSongToDelete(null);
    try {
      // Hapus file dari penyimpanan HP via Capacitor
      if ((window as any).Capacitor?.isNativePlatform()) {
        try {
          const { Filesystem, Directory } = await import('@capacitor/filesystem');
          await Filesystem.deleteFile({ path: song.path });
        } catch (fsErr: any) {
          console.warn('Filesystem delete error (mungkin file sudah tidak ada):', fsErr);
        }
      }
      // Blacklist juga agar tidak muncul kembali
      await addHiddenSong(song.id, song.path);
      await removeSongFromState(song);
      toast(`"${song.title}" berhasil dihapus dari HP!`, 'success');
    } catch (e: any) {
      toast('Gagal menghapus file: ' + e.message, 'error');
    }
  };

  // Rename song handler
  const handleRenameSongClick = (song: LocalSong) => {
    setSongToRename(song);
    setIsRenameOpen(true);
  };

  // Download satu lagu cloud ke offline — lagu tetap muncul di cloud tab
  const handleDownloadSong = async (song: LocalSong) => {
    if (downloadingId) return;
    setDownloadingId(song.id);
    try {
      await ensureMusicFolder();
      const originalId = song.id.replace('cloud-', '');
      const res = await fetch('/api/cloud-songs');
      const allCloud = await res.json();
      const originalSong = allCloud.find((s: any) => String(s.id) === String(originalId));
      if (!originalSong) throw new Error('Data lagu tidak ditemukan');

      const downloaded = await downloadCloudSong(originalSong, (msg) => {
        toast(msg, 'info');
      });
      if (downloaded) {
        // Auto rescan untuk langsung masuk ke offline list
        toast(`"${song.title}" berhasil disimpan! Memindai ulang library...`, 'info');
        if (isCapacitorActive()) {
          const permitted = await requestMobileStoragePermission();
          if (permitted) {
            const freshSongs = await scanAllMobileStorage();
            // Keep valid downloaded songs
            const existingDb = await getSongs();
            const downloadedSongs = existingDb.filter(s => s.isDownloaded);
            const mergedSongs = [...freshSongs, ...downloadedSongs.filter(dl => !freshSongs.some(f => f.id === dl.id))];
            await clearSongs();
            await saveSongs(mergedSongs);
            setLocalSongs(mergedSongs);
          }
        } else {
          const songs = await getSongs();
          setLocalSongs(songs.filter(s => !s.isCloud));
        }
        // Mark as downloaded in UI (cloud song stays in list)
        const dlId = `cloud-dl-${originalId}`;
        setDownloadedCloudIds(prev => new Set([...prev, dlId]));
        toast(`"${song.title}" berhasil disimpan ke Offline! Bisa diputar kapan saja.`, 'success');
      }
    } catch (e: any) {
      toast('Gagal download: ' + e.message, 'error');
    } finally {
      setDownloadingId(null);
    }
  };

  // Refresh Cloud — cek lagu terbaru di cloud (tidak download otomatis)
  const handleRefreshCloud = async () => {
    setSyncingCloud(true);
    try {
      await loadCloudSongs();
      toast(`☁️ Daftar lagu cloud diperbarui! ${cloudSongs.length} lagu tersedia.`, 'success');
    } catch (e: any) {
      toast('Gagal refresh cloud: ' + e.message, 'error');
    } finally {
      setSyncingCloud(false);
    }
  };

  // Delete cloud song (admin only)
  const handleDeleteCloudSong = async (song: LocalSong) => {
    if (!confirm(`Hapus "${song.title}" dari cloud? File akan dihapus dari database.`)) return;
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error('Tidak terautentikasi');
      const originalId = song.id.replace('cloud-', '');
      const res = await fetch('/api/cloud-songs', {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ id: originalId }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Gagal hapus');
      }
      setCloudSongs(prev => prev.filter(s => s.id !== song.id));
      toast(`"${song.title}" berhasil dihapus dari cloud.`, 'success');
    } catch (e: any) {
      toast('Gagal hapus dari cloud: ' + e.message, 'error');
    }
  };

  // Sembunyikan semua lagu yang terfilter dari library
  const handleHideAll = async () => {
    const songsToHide = getFilteredSongs().filter(s => !s.isCloud);
    setIsDeleteAllOpen(false);
    try {
      const hideIds = new Set(songsToHide.map(s => s.id));
      for (const song of songsToHide) {
        await addHiddenSong(song.id, song.path);
        await deleteSong(song.id);
        if (favorites.includes(song.id)) {
          await toggleFavorite(song.id);
        }
      }
      setFavorites(prev => prev.filter(id => !hideIds.has(id)));
      setLocalSongs(prev => prev.filter(s => !hideIds.has(s.id)));
      if (songsToHide.some(s => s.id === playerState.currentSong?.id)) {
        audioManager.seek(0);
        if (playerState.isPlaying) audioManager.togglePlay();
      }
      toast(`${songsToHide.length} lagu disembunyikan dari library.`, 'success');
    } catch (e: any) {
      toast('Gagal menyembunyikan: ' + e.message, 'error');
    }
  };

  // Hapus semua file dari HP + sembunyikan dari library
  const handleDeleteAllFromDevice = async () => {
    const songsToDelete = getFilteredSongs().filter(s => !s.isCloud);
    setIsDeleteAllOpen(false);
    try {
      const deleteIds = new Set(songsToDelete.map(s => s.id));
      for (const song of songsToDelete) {
        // Delete file from storage (Capacitor)
        if ((window as any).Capacitor?.isNativePlatform()) {
          try {
            const { Filesystem } = await import('@capacitor/filesystem');
            await Filesystem.deleteFile({ path: song.path });
          } catch (fsErr) {
            console.warn('File delete error:', fsErr);
          }
        }
        await addHiddenSong(song.id, song.path);
        await deleteSong(song.id);
        if (favorites.includes(song.id)) {
          await toggleFavorite(song.id);
        }
      }
      setFavorites(prev => prev.filter(id => !deleteIds.has(id)));
      setLocalSongs(prev => prev.filter(s => !deleteIds.has(s.id)));
      if (songsToDelete.some(s => s.id === playerState.currentSong?.id)) {
        audioManager.seek(0);
        if (playerState.isPlaying) audioManager.togglePlay();
      }
      toast(`${songsToDelete.length} lagu berhasil dihapus dari HP!`, 'success');
    } catch (e: any) {
      toast('Gagal menghapus: ' + e.message, 'error');
    }
  };

  // Delete all filtered songs (from DB only, file stays)
  const handleDeleteAll = async () => {
    // Hanya hapus lagu local/offline, bukan cloud streaming
    const songsToDelete = getFilteredSongs().filter(s => !s.isCloud);
    setIsDeleteAllOpen(false);
    try {
      const deleteIds = new Set(songsToDelete.map(s => s.id));
      for (const song of songsToDelete) {
        await deleteSong(song.id);
        if (favorites.includes(song.id)) {
          await toggleFavorite(song.id);
        }
      }
      setFavorites(prev => prev.filter(id => !deleteIds.has(id)));
      setLocalSongs(prev => prev.filter(s => !deleteIds.has(s.id)));
      if (songsToDelete.some(s => s.id === playerState.currentSong?.id)) {
        audioManager.seek(0);
        if (playerState.isPlaying) audioManager.togglePlay();
      }
      toast(`${songsToDelete.length} lagu berhasil dihapus!`, 'success');
      // Tidak memanggil loadLocalDataAndSync() agar lagu yang dihapus tidak muncul lagi
    } catch (e: any) {
      toast('Gagal menghapus: ' + e.message, 'error');
    }
  };

  // Playlist actions
  const handleCreatePlaylist = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newPlaylistName.trim()) return;

    const newPl: LocalPlaylist = {
      id: Math.random().toString(36).substring(2, 9),
      name: newPlaylistName.trim(),
      description: 'Local custom playlist',
      songIds: [],
      createdAt: Date.now()
    };

    await savePlaylist(newPl);
    setPlaylists(prev => [...prev, newPl]);
    setNewPlaylistName('');
    setShowCreatePlaylistRow(false);
    toast(`Playlist "${newPl.name}" berhasil dibuat`, 'success');
  };

  const handleDeletePlaylist = async (id: string, name: string) => {
    if (confirm(`Apakah Anda yakin ingin menghapus playlist "${name}"?`)) {
      await deletePlaylist(id);
      setPlaylists(prev => prev.filter(p => p.id !== id));
      if (selectedPlaylistId === id) {
        setSelectedPlaylistId(null);
      }
      toast(`Playlist "${name}" dihapus`, 'info');
    }
  };

  // Filter and sort songs
  const getFilteredSongs = (): LocalSong[] => {
    // Pisahkan berdasarkan sumber: online (cloud streaming) vs offline (local + downloaded)
    let filtered: LocalSong[];
    if (sourceFilter === 'online') {
      filtered = [...cloudSongs];
    } else if (sourceFilter === 'offline') {
      filtered = [...localSongs];
    } else {
      filtered = [...allSongs];
    }

    // Search query
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      filtered = filtered.filter(
        s => s.title.toLowerCase().includes(q) ||
             s.artist.toLowerCase().includes(q) ||
             s.album.toLowerCase().includes(q)
      );
    }

    // Duration filter
    if (durationFilter === 'under1') {
      filtered = filtered.filter(s => s.duration > 0 && s.duration < 60);
    } else if (durationFilter === '1to2') {
      filtered = filtered.filter(s => s.duration >= 60 && s.duration < 120);
    } else if (durationFilter === 'over2') {
      filtered = filtered.filter(s => s.duration >= 120);
    }

    // Sorting
    filtered.sort((a, b) => {
      let valA = (a[sortBy] || '').toString().toLowerCase();
      let valB = (b[sortBy] || '').toString().toLowerCase();

      if (sortOrder === 'asc') {
        return valA.localeCompare(valB);
      } else {
        return valB.localeCompare(valA);
      }
    });

    return filtered;
  };

  const formatTime = (secs: number) => {
    if (isNaN(secs) || secs === 0) return '0:00';
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  return (
    <div
      className={`min-h-screen bg-[#0a0a0a] text-white flex flex-col font-body w-full max-w-full overflow-x-hidden ${playerState.currentSong ? 'pb-[72px]' : 'pb-8'}`}
    >
      {/* Subtle top glow — constrained to not overflow */}
      <div className="w-full h-32 bg-gradient-to-b from-[#c8f500]/5 to-transparent pointer-events-none flex-shrink-0" style={{marginBottom: '-8rem'}}></div>

      {/* Header - scrolls with content */}
      <header className="relative z-30 px-3 py-2 border-b border-white/5 flex flex-col gap-2">
        {/* Row 1: Logo + icon-only action buttons */}
        <div className="flex items-center gap-2 justify-between">

          {/* Logo */}
          <div className="flex items-center gap-2 flex-shrink-0">
            <div className="relative">
              <div className="p-1.5 rounded-lg bg-[#111] border border-[#c8f500]/20">
                <Disc className="w-4 h-4 text-[#c8f500] animate-spin-slow" />
              </div>
              {updateInfo && (
                <button onClick={() => setShowUpdateDialog(true)} className="absolute -top-1.5 -right-1.5">
                  <div className="w-4 h-4 rounded-full bg-red-500 border border-[#0a0a0a] flex items-center justify-center">
                    <span className="text-white font-black text-[7px]">!</span>
                  </div>
                </button>
              )}
            </div>
            <div>
              <h1 className="text-2xl font-heading text-[#c8f500] tracking-widest leading-none">KYOKOBEAT</h1>
              <p className="text-[8px] text-gray-600 uppercase tracking-widest">OFFLINE & CLOUD PLAYER</p>
            </div>
          </div>

          {/* Right: icon-only action buttons */}
          <div className="flex items-center gap-1">
            {/* Help */}
            <button
              onClick={() => setShowHelp(!showHelp)}
              title="Bantuan"
              className="w-8 h-8 rounded-full bg-[#111] border border-gray-800 hover:border-[#c8f500]/40 text-gray-500 hover:text-[#c8f500] transition-colors cursor-pointer flex items-center justify-center flex-shrink-0"
            >
              <HelpCircle className="w-3.5 h-3.5" />
            </button>

            {/* Cloud account */}
            <CloudSyncIndicator
              user={user}
              onLoginClick={() => setIsAuthOpen(true)}
              onLogoutSuccess={() => setUser(null)}
              favorites={favorites}
              playlists={playlists}
              onSyncComplete={loadLocalDataAndSync}
            />

            {/* Rescan folder */}
            <button
              onClick={handleRescan}
              disabled={scanning}
              title="Rescan Folder"
              className="w-8 h-8 rounded-full bg-[#111] border border-[#c8f500]/30 hover:border-[#c8f500] text-[#c8f500] transition-all cursor-pointer flex items-center justify-center flex-shrink-0"
            >
              {scanning
                ? <Loader2 className="w-3.5 h-3.5 animate-spin" />
                : <FolderSync className="w-3.5 h-3.5" />}
            </button>

            {/* Refresh cloud */}
            <button
              onClick={handleRefreshCloud}
              disabled={syncingCloud}
              title="Refresh Cloud"
              className="w-8 h-8 rounded-full bg-[#111] border border-blue-500/30 hover:border-blue-400 text-blue-400 transition-all cursor-pointer flex items-center justify-center flex-shrink-0"
            >
              {syncingCloud
                ? <Loader2 className="w-3.5 h-3.5 animate-spin" />
                : <RefreshCw className="w-3.5 h-3.5" />}
            </button>

            {/* YouTube download */}
            <button
              onClick={() => setIsYtModalOpen(true)}
              title="Download dari YouTube"
              className="w-8 h-8 rounded-full bg-red-500/10 border border-red-500/40 hover:border-red-500 text-red-400 transition-all cursor-pointer flex items-center justify-center flex-shrink-0"
            >
              <Youtube className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* Row 2: Search bar */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-500" />
          <input
            type="text"
            placeholder="Cari lagu, artis, album..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-8 pr-4 py-2 bg-[#111] border border-[#c8f500]/10 rounded-full text-sm text-white placeholder-gray-600 focus:outline-none focus:border-[#c8f500]/40 transition-all"
          />
        </div>
      </header>

      {/* Permission Warning Banner */}
      {needPermission && (
        <div className="bg-yellow-500/10 border-b border-yellow-500/20 text-yellow-500 p-3 text-xs font-body flex items-center justify-between gap-4 animate-fade-in relative z-10">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 flex-shrink-0 animate-bounce" />
            <span>
              <strong>Izin Akses Folder Kedaluwarsa:</strong> Browser membatasi akses file lokal demi keamanan setelah halaman dimuat ulang. Klik tombol di kanan untuk mengaktifkan kembali pemutaran lagu lokal Anda secara instan.
            </span>
          </div>
          <button
            onClick={handleGrantPermission}
            className="px-3 py-1.5 bg-yellow-500 hover:bg-yellow-600 text-black font-bold rounded-lg transition-colors cursor-pointer flex-shrink-0"
          >
            Aktifkan Izin Lokal
          </button>
        </div>
      )}

      {/* Background Syncing Indicator */}
      {syncingBackground && (
        <div className="bg-[#c8f500]/10 border-b border-[#c8f500]/20 text-[#c8f500] p-2 text-xs font-body flex items-center justify-center gap-2 animate-fade-in relative z-10">
          <RefreshCw className="w-3.5 h-3.5 animate-spin" />
          <span>KyokoBeat sedang mendeteksi file lagu baru/terhapus di folder Anda secara otomatis...</span>
        </div>
      )}

      {/* Help / Explanation Panel */}
      {showHelp && (
        <div className="bg-[#111] border-b border-[#c8f500]/20 p-5 font-body text-xs text-gray-300 relative z-10 animate-scale-up">
          <div className="max-w-4xl mx-auto space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-[#c8f500] font-heading text-lg tracking-wider">TANYA JAWAB KYOKOBEAT</h3>
              <button onClick={() => setShowHelp(false)} className="text-gray-500 hover:text-white">
                <X className="w-4 h-4" />
              </button>
            </div>
            
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <h4 className="font-bold text-white mb-1">1. Mengapa ada pesan "Gagal memuat lagu"?</h4>
                <p className="leading-relaxed text-gray-400">
                  <strong>Untuk Lagu Lokal (Offline):</strong> Browser secara default mencabut izin akses folder setiap kali Anda menutup atau memuat ulang (refresh) tab demi keamanan privasi Anda. Cukup klik tombol <strong>"Aktifkan Izin Lokal"</strong> pada banner kuning di atas untuk memulihkan akses tanpa perlu scan ulang.
                  <br />
                  <strong>Untuk Lagu Cloud (Online):</strong> Jika koneksi internet Anda tidak stabil, lagu cloud mungkin gagal dimuat sementara. Kami telah melengkapi pemutar dengan fitur fallback otomatis tanpa CORS sehingga tetap dapat diputar bahkan jika terhalang proteksi server.
                </p>
              </div>

              <div>
                <h4 className="font-bold text-white mb-1">2. Apakah saya harus rescan manual jika menambah lagu baru?</h4>
                <p className="leading-relaxed text-gray-400">
                  <strong>Tidak perlu!</strong> KyokoBeat memiliki fitur **Incremental Auto-Sync**. Setiap kali Anda membuka aplikasi atau mengaktifkan kembali izin folder, KyokoBeat akan secara otomatis memindai folder tersebut di latar belakang.
                  <br />
                  Aplikasi hanya akan memproses file lagu baru yang ditambahkan atau menghapus file lagu yang sudah Anda hapus dari folder tersebut, **tanpa perlu memindai ulang lagu-lagu lama**. Proses ini berjalan super cepat (kurang dari 1 detik)!
                </p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Main Content Area */}
      <main className="flex-1 max-w-full w-full mx-auto p-3 grid grid-cols-1 lg:grid-cols-4 gap-4 relative z-10 overflow-x-hidden">
        {/* Left Side: Navigation / Playlists */}
        <div className="lg:col-span-1 space-y-6">
          {/* Library Tabs */}
          <div className="p-2 bg-[#111] rounded-xl border border-white/5 space-y-1">
            {/* Main tabs */}
            <button
              onClick={() => { setActiveTab('library'); setSelectedPlaylistId(null); }}
              className={`w-full flex items-center gap-3 p-3 rounded-lg text-sm font-semibold transition-all cursor-pointer ${
                activeTab === 'library' && !selectedPlaylistId
                  ? 'bg-[#c8f500] text-black shadow-[0_0_15px_rgba(200,245,0,0.2)]'
                  : 'text-gray-400 hover:text-white hover:bg-white/5'
              }`}
            >
              <Music className="w-4 h-4" />
              <span>Semua Lagu</span>
              <span className="ml-auto text-xs opacity-60">({allSongs.length})</span>
            </button>

            {/* Online / Offline sub-filter (only visible in library tab) */}
            {activeTab === 'library' && !selectedPlaylistId && (
              <div className="ml-2 border-l border-[#c8f500]/20 pl-2 space-y-0.5 animate-fade-in">
                <button
                  onClick={() => setSourceFilter('online')}
                  className={`w-full flex items-center gap-2 px-2.5 py-2 rounded-lg text-xs font-semibold transition-all cursor-pointer ${
                    sourceFilter === 'online'
                      ? 'text-blue-400 bg-blue-500/10'
                      : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
                  }`}
                >
                  <Cloud className="w-3 h-3 flex-shrink-0" />
                  Online
                  <span className="ml-auto opacity-60">({cloudSongs.length})</span>
                </button>
                <button
                  onClick={() => setSourceFilter('offline')}
                  className={`w-full flex items-center gap-2 px-2.5 py-2 rounded-lg text-xs font-semibold transition-all cursor-pointer ${
                    sourceFilter === 'offline'
                      ? 'text-green-400 bg-green-500/10'
                      : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
                  }`}
                >
                  <Laptop className="w-3 h-3 flex-shrink-0" />
                  Offline
                  <span className="ml-auto opacity-60">({localSongs.length})</span>
                </button>
              </div>
            )}

            <button
              onClick={() => { setActiveTab('favorites'); setSelectedPlaylistId(null); }}
              className={`w-full flex items-center gap-3 p-3 rounded-lg text-sm font-semibold transition-all cursor-pointer ${
                activeTab === 'favorites'
                  ? 'bg-[#c8f500] text-black shadow-[0_0_15px_rgba(200,245,0,0.2)]'
                  : 'text-gray-400 hover:text-white hover:bg-white/5'
              }`}
            >
              <Heart className="w-4 h-4" />
              <span>Lagu Favorit</span>
              <span className="ml-auto text-xs opacity-60">({favorites.length})</span>
            </button>

            <button
              onClick={() => { setActiveTab('playlists'); }}
              className={`w-full flex items-center gap-3 p-3 rounded-lg text-sm font-semibold transition-all cursor-pointer ${
                activeTab === 'playlists' && !selectedPlaylistId
                  ? 'bg-[#c8f500] text-black shadow-[0_0_15px_rgba(200,245,0,0.2)]'
                  : 'text-gray-400 hover:text-white hover:bg-white/5'
              }`}
            >
              <FolderHeart className="w-4 h-4" />
              <span>Playlist Custom</span>
              <span className="ml-auto text-xs opacity-60">({playlists.length})</span>
            </button>
          </div>

          {/* Playlist Section (Visible when playlists active or on desktop) */}
          <div className="p-4 bg-[#111] rounded-xl border border-white/5 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider">PLAYLISTS</h3>
              <button
                onClick={() => setShowCreatePlaylistRow(!showCreatePlaylistRow)}
                className="p-1 hover:text-[#c8f500] transition-colors cursor-pointer"
                title="Buat Playlist"
              >
                <Plus className="w-4 h-4" />
              </button>
            </div>

            {/* Create Playlist Form Row */}
            {showCreatePlaylistRow && (
              <form onSubmit={handleCreatePlaylist} className="flex gap-2">
                <input
                  type="text"
                  placeholder="Nama playlist..."
                  value={newPlaylistName}
                  onChange={(e) => setNewPlaylistName(e.target.value)}
                  className="flex-1 px-3 py-1.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-xs text-white focus:outline-none focus:border-[#c8f500]"
                />
                <button
                  type="submit"
                  className="px-3 py-1.5 bg-[#c8f500] text-black text-xs font-bold rounded-lg hover:shadow-[0_0_10px_rgba(200,245,0,0.3)] transition-all cursor-pointer"
                >
                  Buat
                </button>
              </form>
            )}

            <div className="space-y-1.5 max-h-48 overflow-y-auto pr-1">
              {playlists.length === 0 ? (
                <p className="text-xs text-gray-600 text-center py-4">Belum ada playlist.</p>
              ) : (
                playlists.map((pl) => (
                  <div
                    key={pl.id}
                    className={`group/item flex items-center justify-between p-2 rounded-lg text-xs font-medium cursor-pointer transition-colors ${
                      selectedPlaylistId === pl.id
                        ? 'bg-[#c8f500]/10 border border-[#c8f500]/30 text-[#c8f500]'
                        : 'bg-[#0a0a0a] border border-transparent text-gray-400 hover:text-white hover:bg-white/5'
                    }`}
                  >
                    <div
                      onClick={() => {
                        setActiveTab('playlists');
                        setSelectedPlaylistId(pl.id);
                      }}
                      className="flex-1 truncate pr-2"
                    >
                      <span className="font-semibold block truncate">{pl.name}</span>
                      <span className="text-[10px] text-gray-500">{pl.songIds.length} Lagu</span>
                    </div>
                    <button
                      onClick={() => handleDeletePlaylist(pl.id, pl.name)}
                      className="opacity-0 group-hover/item:opacity-100 p-1 text-gray-500 hover:text-red-500 transition-all"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        {/* Right Side: Song List / Library View */}
        <div className="lg:col-span-3 space-y-4">
          {/* Scanning Overlay / Progress */}
          {scanning && (
            <div className="p-4 rounded-xl bg-[#c8f500]/10 border border-[#c8f500]/20 animate-pulse flex items-center gap-4">
              <Loader2 className="w-8 h-8 text-[#c8f500] animate-spin" />
              <div className="flex-1 min-w-0">
                <div className="flex justify-between items-center mb-1">
                  <span className="text-sm font-semibold text-[#c8f500]">Sedang menscan direktori musik...</span>
                  <span className="text-xs text-gray-400">{scanProgress.scannedCount} / {scanProgress.totalFiles}</span>
                </div>
                <div className="w-full bg-[#111] h-1.5 rounded-full overflow-hidden">
                  <div
                    className="bg-[#c8f500] h-full transition-all duration-300"
                    style={{ width: `${scanProgress.totalFiles > 0 ? (scanProgress.scannedCount / scanProgress.totalFiles) * 100 : 0}%` }}
                  ></div>
                </div>
                <p className="text-[10px] text-gray-500 truncate mt-1">File: {scanProgress.currentFileName}</p>
              </div>
            </div>
          )}

          {/* Duration Filter + Delete All */}
          <div className="flex flex-wrap items-center gap-2 p-3 bg-[#111] rounded-xl border border-white/5">
            <span className="text-xs text-gray-500 mr-1">Durasi:</span>
            {([
              { key: 'all', label: 'Semua' },
              { key: 'under1', label: '< 1 menit' },
              { key: '1to2', label: '1–2 menit' },
              { key: 'over2', label: '> 2 menit' },
            ] as const).map(({ key, label }) => (
              <button
                key={key}
                onClick={() => setDurationFilter(key)}
                className={`px-2.5 py-1 rounded-md text-xs font-semibold transition-all cursor-pointer ${
                  durationFilter === key
                    ? 'bg-[#c8f500]/10 border border-[#c8f500]/30 text-[#c8f500]'
                    : 'bg-[#0a0a0a] border border-transparent text-gray-400 hover:text-white'
                }`}
              >
                {label}
              </button>
            ))}
            {durationFilter !== 'all' && (
              <button
                onClick={() => setIsDeleteAllOpen('choose')}
                className="ml-auto flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-semibold bg-red-500/10 border border-red-500/30 text-red-400 hover:bg-red-500/20 transition-all cursor-pointer"
              >
                <Trash2 className="w-3.5 h-3.5" />
                Hapus Semua ({getFilteredSongs().length})
              </button>
            )}
          </div>

          {/* Sorting / View controls */}
          <div className="flex items-center justify-between p-3 bg-[#111] rounded-xl border border-white/5">
            <div className="flex items-center gap-3">
              <span className="text-xs text-gray-500 flex items-center gap-1">
                <SlidersHorizontal className="w-3.5 h-3.5 text-gray-400" />
                Urutkan:
              </span>
              <div className="flex gap-1.5">
                {(['title', 'artist', 'album'] as const).map((key) => (
                  <button
                    key={key}
                    onClick={() => {
                      if (sortBy === key) {
                        setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
                      } else {
                        setSortBy(key);
                        setSortOrder('asc');
                      }
                    }}
                    className={`px-2.5 py-1 rounded-md text-xs font-semibold capitalize transition-all cursor-pointer ${
                      sortBy === key
                        ? 'bg-[#c8f500]/10 border border-[#c8f500]/30 text-[#c8f500]'
                        : 'bg-[#0a0a0a] border border-transparent text-gray-400 hover:text-white'
                    }`}
                  >
                    {key === 'title' ? 'Judul' : key === 'artist' ? 'Artis' : 'Album'}
                    {sortBy === key && (
                      <ArrowUpDown className="w-3 h-3 inline-block ml-1" />
                    )}
                  </button>
                ))}
              </div>
            </div>

            {/* View Mode controls */}
            <div className="flex items-center gap-2">
              <button
                onClick={() => setViewMode('grid')}
                className={`p-1.5 rounded-md transition-colors cursor-pointer ${viewMode === 'grid' ? 'text-[#c8f500] bg-white/5' : 'text-gray-500 hover:text-white'}`}
              >
                <LayoutGrid className="w-4 h-4" />
              </button>
              <button
                onClick={() => setViewMode('list')}
                className={`p-1.5 rounded-md transition-colors cursor-pointer ${viewMode === 'list' ? 'text-[#c8f500] bg-white/5' : 'text-gray-500 hover:text-white'}`}
              >
                <List className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* Songs Display Grid / List */}
          <div>
            {/* If a playlist is selected, display its details */}
            {activeTab === 'playlists' && selectedPlaylistId && (
              <div className="mb-4 p-4 rounded-xl bg-[#111] border border-white/5 flex justify-between items-center animate-fade-in">
                <div>
                  <h2 className="text-2xl font-heading text-[#c8f500] tracking-wider">
                    PLAYLIST: {playlists.find(p => p.id === selectedPlaylistId)?.name.toUpperCase()}
                  </h2>
                  <p className="text-xs text-gray-400 font-body">
                    {playlists.find(p => p.id === selectedPlaylistId)?.songIds.length || 0} Lagu • Local Playlist
                  </p>
                </div>
                <button
                  onClick={() => setSelectedPlaylistId(null)}
                  className="px-3 py-1.5 bg-transparent border border-gray-800 hover:border-gray-600 text-gray-400 hover:text-white text-xs font-semibold rounded-lg transition-colors cursor-pointer"
                >
                  Kembali ke Semua Playlist
                </button>
              </div>
            )}

            {/* Online/Offline header banner */}
            {activeTab === 'library' && !selectedPlaylistId && sourceFilter !== 'all' && (
              <div className={`mb-4 p-4 rounded-xl border animate-fade-in flex items-center justify-between ${
                sourceFilter === 'online'
                  ? 'bg-blue-500/5 border-blue-500/20'
                  : 'bg-green-500/5 border-green-500/20'
              }`}>
                <div>
                  <h2 className={`text-xl font-heading tracking-wider flex items-center gap-2 ${sourceFilter === 'online' ? 'text-blue-400' : 'text-green-400'}`}>
                    {sourceFilter === 'online' ? <Cloud className="w-5 h-5" /> : <Laptop className="w-5 h-5" />}
                    {sourceFilter === 'online' ? 'LAGU ONLINE (STREAMING)' : 'LAGU OFFLINE (LOKAL)'}
                  </h2>
                  <p className="text-xs text-gray-400 font-body mt-1">
                    {sourceFilter === 'online'
                      ? `${cloudSongs.length} lagu tersedia untuk streaming. Klik download untuk simpan ke offline.`
                      : `${localSongs.length} lagu tersimpan di perangkat. Termasuk lagu yang sudah didownload dari cloud.`
                    }
                  </p>
                </div>
              </div>
            )}

            {/* If on favorites tab, display favorit header */}
            {activeTab === 'favorites' && (
              <div className="mb-4 p-4 rounded-xl bg-[#111] border border-white/5 animate-fade-in">
                <h2 className="text-2xl font-heading text-[#c8f500] tracking-wider">LAGU FAVORIT ANDA</h2>
                <p className="text-xs text-gray-400 font-body">Menampilkan semua lagu yang Anda tandai sebagai favorit.</p>
              </div>
            )}

            {/* Songs render */}
            {(() => {
              let displaySongs: LocalSong[] = [];
              if (activeTab === 'library') {
                displaySongs = getFilteredSongs();
              } else if (activeTab === 'favorites') {
                displaySongs = getFilteredSongs().filter(s => favorites.includes(s.id));
              } else if (activeTab === 'playlists') {
                if (selectedPlaylistId) {
                  const pl = playlists.find(p => p.id === selectedPlaylistId);
                  if (pl) {
                    displaySongs = getFilteredSongs().filter(s => pl.songIds.includes(s.id));
                  }
                } else {
                  // If playlists tab is active but no playlist selected, show playlist list cards
                  return (
                    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
                      {playlists.map((pl) => (
                        <div
                          key={pl.id}
                          className="p-5 rounded-xl bg-[#111] border border-[#c8f500]/5 hover:border-[#c8f500]/20 hover:shadow-[0_0_20px_rgba(200,245,0,0.05)] transition-all transform hover:-translate-y-1 relative group"
                        >
                          <FolderHeart className="w-10 h-10 text-[#c8f500] mb-3" />
                          <h3 className="text-lg font-bold truncate">{pl.name}</h3>
                          <p className="text-xs text-gray-400 mt-1">{pl.songIds.length} Lagu</p>
                          
                          <div className="flex gap-2 mt-4">
                            <button
                              onClick={() => {
                                setSelectedPlaylistId(pl.id);
                              }}
                              className="px-3 py-1.5 bg-[#c8f500] text-black text-xs font-bold rounded-lg cursor-pointer"
                            >
                              Buka Playlist
                            </button>
                            <button
                              onClick={() => handleDeletePlaylist(pl.id, pl.name)}
                              className="px-3 py-1.5 bg-[#1a1a1a] border border-red-500/20 text-red-400 hover:bg-red-500/10 text-xs font-bold rounded-lg cursor-pointer"
                            >
                              Hapus
                            </button>
                          </div>
                        </div>
                      ))}
                      {playlists.length === 0 && (
                        <div className="col-span-full text-center py-12 bg-[#111] rounded-xl border border-white/5">
                          <FolderHeart className="w-12 h-12 text-[#c8f500] mx-auto mb-3 opacity-30" />
                          <h3 className="text-lg font-semibold text-gray-400">Belum ada playlist custom</h3>
                          <p className="text-xs text-gray-500 mt-1 max-w-xs mx-auto">Klik tombol plus (+) di bagian kiri menu playlist untuk membuat playlist kustom baru.</p>
                        </div>
                      )}
                    </div>
                  );
                }
              }

              if (displaySongs.length === 0) {
                return (
                  <div className="text-center py-16 bg-[#111] rounded-xl border border-white/5">
                    <Music className="w-16 h-12 text-[#c8f500] mx-auto mb-3 opacity-30" />
                    <h3 className="text-lg font-semibold text-gray-400">Tidak ada lagu yang ditemukan</h3>
                    <p className="text-xs text-gray-500 mt-1 max-w-xs mx-auto">
                      {searchQuery ? 'Coba cari kata kunci lain.' : 'Silakan gunakan tombol "Rescan Folder" di kanan atas untuk memindai lagu lokal dari perangkat Anda.'}
                    </p>
                  </div>
                );
              }

              return (
                <div className={viewMode === 'grid' ? 'grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4' : 'flex flex-col gap-2'}>
                  {displaySongs.map((song) => (
                    <div
                      key={song.id}
                      onClick={(e) => {
                        // Play only if tap is NOT on an action button (heart, menu, download, etc.)
                        if (!(e.target as HTMLElement).closest('button') && !(e.target as HTMLElement).closest('a')) {
                          handlePlaySong(song);
                        }
                      }}
                      className="cursor-pointer"
                    >
                      <SongCard
                        song={song}
                        isCurrent={playerState.currentSong?.id === song.id}
                        isPlaying={playerState.isPlaying}
                        isFav={favorites.includes(song.id)}
                        onPlay={() => handlePlaySong(song)}
                        onToggleFav={() => handleToggleFav(song)}
                        onAddToPlaylist={() => {
                          setSongToAddToPlaylist(song);
                          setIsPlaylistOpen(true);
                        }}
                        onRename={handleRenameSongClick}
                        onDelete={handleDeleteSong}
                        onDownload={song.isCloud ? () => handleDownloadSong(song) : undefined}
                        onDeleteCloud={song.isCloud && user?.email === 'kyokomd2006@gmail.com' ? () => handleDeleteCloudSong(song) : undefined}
                        isDownloading={downloadingId === song.id}
                        isDownloaded={song.isCloud ? downloadedCloudIds.has(`cloud-dl-${song.id.replace('cloud-', '')}`) : false}
                      />
                    </div>
                  ))}
                </div>
              );
            })()}
          </div>
        </div>
      </main>

      {/* ─── MINI PLAYER (Spotify-style compact bar) ─── */}
      {playerState.currentSong && (
        <div
          className="fixed bottom-0 left-0 right-0 z-50 px-2 overflow-hidden"
          style={{ paddingBottom: 'max(8px, env(safe-area-inset-bottom, 8px))' }}
        >
          <div
            className="bg-[#1e1e1e] rounded-xl overflow-hidden shadow-[0_-4px_24px_rgba(0,0,0,0.6)] cursor-pointer active:scale-[0.99] transition-transform"
            onClick={() => setShowFullPlayer(true)}
          >
            {/* Thin progress bar at top */}
            <div className="h-[2px] bg-white/10">
              <div
                className="h-full bg-[#c8f500]"
                style={{
                  width: `${playerState.duration ? (playerState.currentTime / playerState.duration) * 100 : 0}%`,
                  transition: 'width 0.5s linear',
                }}
              />
            </div>
            <div className="flex items-center gap-3 px-3 py-2.5">
              {/* Album art */}
              <div className="w-10 h-10 rounded-lg overflow-hidden bg-[#111] flex-shrink-0 relative">
                {playerState.currentSong.cover ? (
                  <img src={playerState.currentSong.cover} alt="" className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                ) : null}
                <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-[#1a2200] to-[#111]">
                  <Disc className="w-5 h-5 text-[#c8f500]/50" />
                </div>
              </div>
              {/* Song info */}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-white truncate leading-tight">{playerState.currentSong.title}</p>
                <p className="text-xs text-gray-400 truncate">{playerState.currentSong.artist}</p>
              </div>
              {/* Controls */}
              <div className="flex items-center gap-0.5" onClick={(e) => e.stopPropagation()}>
                <button onClick={playPrevTrack} className="p-2 text-gray-400 active:text-white transition-colors cursor-pointer">
                  <SkipBack className="w-5 h-5 fill-current" />
                </button>
                <button onClick={() => audioManager.togglePlay()} className="p-2 text-white cursor-pointer">
                  {playerState.isPlaying ? (
                    <Pause className="w-6 h-6 fill-current" />
                  ) : (
                    <Play className="w-6 h-6 fill-current ml-0.5" />
                  )}
                </button>
                <button onClick={playNextTrack} className="p-2 text-gray-400 active:text-white transition-colors cursor-pointer">
                  <SkipForward className="w-5 h-5 fill-current" />
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ─── FULL SCREEN PLAYER ─── */}
      {playerState.currentSong && showFullPlayer && (
        <div
          className="fixed inset-0 z-[100] flex flex-col overflow-hidden"
          style={{ background: 'linear-gradient(180deg, #1c2500 0%, #0d0d0d 55%)', touchAction: 'pan-y', overscrollBehavior: 'none' }}
        >
          {/* Top bar */}
          <div className="flex items-center justify-between px-4 pt-10 pb-2 flex-shrink-0">
            <button onClick={() => setShowFullPlayer(false)} className="p-2 text-gray-400 hover:text-white transition-colors cursor-pointer">
              <ChevronDown className="w-6 h-6" />
            </button>
            <div className="text-center">
              <p className="text-[10px] text-gray-500 uppercase tracking-widest">Memutar dari</p>
              <p className="text-xs font-semibold text-white truncate max-w-[180px]">{playerState.currentSong.album || 'Library'}</p>
            </div>
            <div className="w-10" />
          </div>

          {/* Album art + song info */}
          <div className="flex-1 flex flex-col items-center justify-center px-8 gap-5 min-h-0">
            <div
              className="w-full rounded-2xl overflow-hidden bg-[#111] relative"
              style={{
                maxWidth: 'min(280px, 70vw)',
                aspectRatio: '1/1',
                boxShadow: playerState.isPlaying
                  ? '0 24px 64px rgba(200,245,0,0.18), 0 0 0 1px rgba(200,245,0,0.08)'
                  : '0 24px 64px rgba(0,0,0,0.8)',
                transform: playerState.isPlaying ? 'scale(1)' : 'scale(0.94)',
                transition: 'transform 0.4s cubic-bezier(0.34,1.56,0.64,1), box-shadow 0.4s ease',
              }}
            >
              {playerState.currentSong.cover ? (
                <img src={playerState.currentSong.cover} alt={playerState.currentSong.title} className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
              ) : null}
              <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-[#1a2200] to-[#111]">
                <Disc className="w-20 h-20 text-[#c8f500]/30" />
              </div>
            </div>
            <div className="w-full flex items-center justify-between" style={{ maxWidth: 'min(280px, 70vw)' }}>
              <div className="min-w-0 flex-1">
                <h2 className="text-xl font-bold text-white truncate leading-tight">{playerState.currentSong.title}</h2>
                <p className="text-sm text-gray-400 truncate mt-0.5">{playerState.currentSong.artist}</p>
              </div>
              <button
                onClick={() => handleToggleFav(playerState.currentSong!)}
                className={`p-2 ml-3 flex-shrink-0 transition-colors ${favorites.includes(playerState.currentSong.id) ? 'text-[#c8f500]' : 'text-gray-600 hover:text-gray-400'}`}
              >
                <Heart className={`w-6 h-6 ${favorites.includes(playerState.currentSong.id) ? 'fill-current' : ''}`} />
              </button>
            </div>
          </div>

          {/* Controls */}
          <div className="px-6 pb-10 space-y-4 flex-shrink-0">
            <div className="space-y-1">
              <input
                type="range"
                min="0"
                max={playerState.duration || 100}
                value={playerState.currentTime}
                onChange={(e) => audioManager.seek(parseFloat(e.target.value))}
                className="w-full h-1 rounded-full appearance-none cursor-pointer outline-none"
                style={{ background: `linear-gradient(to right, #c8f500 ${playerState.duration ? (playerState.currentTime / playerState.duration) * 100 : 0}%, rgba(255,255,255,0.15) 0%)` }}
              />
              <div className="flex justify-between">
                <span className="text-[11px] text-gray-500 font-mono">{formatTime(playerState.currentTime)}</span>
                <span className="text-[11px] text-gray-500 font-mono">{formatTime(playerState.duration)}</span>
              </div>
            </div>
            <div className="flex items-center justify-between">
              <button onClick={() => setShuffle(!shuffle)} className={`p-2 cursor-pointer ${shuffle ? 'text-[#c8f500]' : 'text-gray-600'}`}>
                <Shuffle className="w-5 h-5" />
              </button>
              <button onClick={playPrevTrack} className="p-2 text-white cursor-pointer">
                <SkipBack className="w-7 h-7 fill-current" />
              </button>
              <button
                onClick={() => audioManager.togglePlay()}
                className="w-16 h-16 rounded-full bg-white flex items-center justify-center shadow-lg hover:scale-105 transition-transform cursor-pointer"
              >
                {playerState.isPlaying ? (
                  <Pause className="w-8 h-8 fill-black text-black" />
                ) : (
                  <Play className="w-8 h-8 fill-black text-black ml-1" />
                )}
              </button>
              <button onClick={playNextTrack} className="p-2 text-white cursor-pointer">
                <SkipForward className="w-7 h-7 fill-current" />
              </button>
              <button
                onClick={() => { if (repeat === 'none') setRepeat('all'); else if (repeat === 'all') setRepeat('one'); else setRepeat('none'); }}
                className={`p-2 relative cursor-pointer ${repeat !== 'none' ? 'text-[#c8f500]' : 'text-gray-600'}`}
              >
                <Repeat className="w-5 h-5" />
                {repeat === 'one' && <span className="absolute bottom-1 right-1 bg-[#c8f500] text-black text-[7px] font-bold px-0.5 rounded-full">1</span>}
              </button>
            </div>
            <div className="flex items-center gap-3">
              <button onClick={() => audioManager.toggleMute()} className="text-gray-500 cursor-pointer">
                {playerState.isMuted || playerState.volume === 0 ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
              </button>
              <input
                type="range" min="0" max="1" step="0.05"
                value={playerState.isMuted ? 0 : playerState.volume}
                onChange={(e) => audioManager.setVolume(parseFloat(e.target.value))}
                className="flex-1 h-1 rounded-full appearance-none cursor-pointer outline-none"
                style={{ background: `linear-gradient(to right, rgba(255,255,255,0.7) ${(playerState.isMuted ? 0 : playerState.volume) * 100}%, rgba(255,255,255,0.15) 0%)` }}
              />
            </div>
          </div>
        </div>
      )}

            {/* Auth Modal */}
      <AuthModal
        isOpen={isAuthOpen}
        onClose={() => setIsAuthOpen(false)}
        onAuthSuccess={loadLocalDataAndSync}
      />

      {/* Playlist Modal */}
      <PlaylistModal
        isOpen={isPlaylistOpen}
        onClose={() => {
          setIsPlaylistOpen(false);
          setSongToAddToPlaylist(null);
        }}
        song={songToAddToPlaylist}
        onPlaylistUpdated={loadLocalDataAndSync}
      />

      {/* Rename Metadata Modal */}
      <RenameModal
        isOpen={isRenameOpen}
        onClose={() => {
          setIsRenameOpen(false);
          setSongToRename(null);
        }}
        song={songToRename}
        onRenameSuccess={loadLocalDataAndSync}
      />

      {/* Delete Confirm Modal */}
      <DeleteConfirmModal
        isOpen={isDeleteOpen}
        song={songToDelete}
        onHide={handleHideSong}
        onDeleteFile={handleDeleteFileSong}
        onCancel={() => {
          setIsDeleteOpen(false);
          setSongToDelete(null);
        }}
      />

      {/* YouTube Download Modal */}
      <YtDownloadModal
        isOpen={isYtModalOpen}
        onClose={() => setIsYtModalOpen(false)}
        onDownloadComplete={() => {
          loadLocalDataAndSync();
          setSourceFilter('offline');
        }}
        toast={toast}
      />

      {/* In-App Update Dialog */}
      {showUpdateDialog && updateInfo && (
        <UpdateDialog
          info={updateInfo}
          onDismiss={() => setShowUpdateDialog(false)}
        />
      )}

      {/* Delete All Modal - Choose Action */}
      {isDeleteAllOpen === 'choose' && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
          <div className="relative w-full max-w-sm p-6 rounded-xl bg-[#111] border border-gray-700/50 shadow-[0_0_30px_rgba(0,0,0,0.5)] animate-scale-up">
            <button onClick={() => setIsDeleteAllOpen(false)} className="absolute top-4 right-4 text-gray-400 hover:text-white"><X className="w-5 h-5" /></button>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-gray-700/50 flex items-center justify-center flex-shrink-0">
                <Trash2 className="w-5 h-5 text-gray-300" />
              </div>
              <h3 className="text-xl font-heading text-white tracking-wider">HAPUS SEMUA ({getFilteredSongs().filter(s => !s.isCloud).length} LAGU)</h3>
            </div>
            <p className="text-xs text-gray-400 font-body mb-4">Pilih cara menghapus semua lagu yang terfilter:</p>
            <div className="space-y-3">
              {/* Option 1: Hide All */}
              <button
                type="button"
                onClick={handleHideAll}
                className="w-full p-4 rounded-xl bg-[#1a1a1a] border border-[#c8f500]/20 hover:border-[#c8f500]/50 hover:bg-[#c8f500]/5 text-left transition-all cursor-pointer group"
              >
                <div className="flex items-center gap-3 mb-1">
                  <EyeOff className="w-4 h-4 text-[#c8f500] flex-shrink-0" />
                  <span className="text-sm font-semibold text-white group-hover:text-[#c8f500] transition-colors">Sembunyikan Semua dari Library</span>
                </div>
                <p className="text-xs text-gray-500 ml-7">File tetap di HP, tidak akan muncul lagi meski di-rescan.</p>
              </button>
              {/* Option 2: Delete from Device (Capacitor only) */}
              {(window as any).Capacitor?.isNativePlatform() ? (
                <button
                  type="button"
                  onClick={handleDeleteAllFromDevice}
                  className="w-full p-4 rounded-xl bg-[#1a1a1a] border border-red-500/20 hover:border-red-500/50 hover:bg-red-500/5 text-left transition-all cursor-pointer group"
                >
                  <div className="flex items-center gap-3 mb-1">
                    <Trash2 className="w-4 h-4 text-red-400 flex-shrink-0" />
                    <span className="text-sm font-semibold text-white group-hover:text-red-400 transition-colors">Hapus Semua File dari HP</span>
                  </div>
                  <p className="text-xs text-gray-500 ml-7">File dihapus permanen dari penyimpanan. Tidak bisa dikembalikan.</p>
                </button>
              ) : (
                <div className="w-full p-4 rounded-xl bg-[#1a1a1a] border border-gray-800 opacity-40">
                  <div className="flex items-center gap-3 mb-1">
                    <AlertTriangle className="w-4 h-4 text-yellow-500 flex-shrink-0" />
                    <span className="text-sm font-semibold text-gray-400">Hapus File (hanya di Android)</span>
                  </div>
                  <p className="text-xs text-gray-600 ml-7">Fitur ini hanya tersedia di aplikasi Android KyokoBeat.</p>
                </div>
              )}
            </div>
            <button
              type="button"
              onClick={() => setIsDeleteAllOpen(false)}
              className="w-full mt-4 py-2.5 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg hover:bg-gray-900 transition-colors text-sm cursor-pointer"
            >
              Batal
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
