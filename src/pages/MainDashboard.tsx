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
  RefreshCw
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
  deleteSong
} from '../lib/db';
import { scanDirectoryRecursive, verifyPermission, syncFolderIncremental } from '../lib/scanner';
import { isCapacitorActive, requestMobileStoragePermission, scanAllMobileStorage } from '../lib/mobileScanner';
import { syncAllCloudMusic, ensureMusicFolder } from '../lib/cloudMusic';
import SongCard from '../components/SongCard';
import WaveformVisualizer from '../components/WaveformVisualizer';
import CloudSyncIndicator from '../components/CloudSyncIndicator';
import AuthModal from '../components/AuthModal';
import PlaylistModal from '../components/PlaylistModal';
import RenameModal from '../components/RenameModal';
import DeleteConfirmModal from '../components/DeleteConfirmModal';
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
  const [isDeleteAllOpen, setIsDeleteAllOpen] = useState(false);
  const [durationFilter, setDurationFilter] = useState<'all' | 'under1' | '1to2' | 'over2'>('all');
  const [syncingCloud, setSyncingCloud] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [showCreatePlaylistRow, setShowCreatePlaylistRow] = useState(false);

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

    return () => subscription.unsubscribe();
  }, []);

  // 2. Sync Audio Manager State
  useEffect(() => {
    const unsubscribe = audioManager.subscribe((state) => {
      setPlayerState(state);
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
      const songs = await scanAllMobileStorage();
      if (songs.length !== currentSongs.length) {
        await clearSongs();
        await saveSongs(songs);
        setLocalSongs(songs);
        console.log(`[Auto-Sync Mobile] Updated library with ${songs.length} songs.`);
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

  // Load cloud songs from Vercel API
  const loadCloudSongs = async () => {
    try {
      const res = await fetch('/api/cloud-songs');
      if (res.ok) {
        const data = await res.json();
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
          audioUrl: song.audio_url
        }));
        setCloudSongs(formattedCloudSongs);
      }
    } catch (e) {
      console.warn('Failed to load cloud songs:', e);
    }
  };

  // Combine local and cloud songs
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

  const handleConfirmDelete = async () => {
    const song = songToDelete;
    if (!song) return;
    setIsDeleteOpen(false);
    setSongToDelete(null);
    try {
        await deleteSong(song.id);
        
        // Remove from favorites if favorited
        if (favorites.includes(song.id)) {
          await toggleFavorite(song.id);
          setFavorites(prev => prev.filter(id => id !== song.id));
        }

        // Remove from all custom playlists
        for (const pl of playlists) {
          if (pl.songIds.includes(song.id)) {
            const updatedPl = {
              ...pl,
              songIds: pl.songIds.filter(id => id !== song.id)
            };
            await savePlaylist(updatedPl);
          }
        }

        // Update local state
        setLocalSongs(prev => prev.filter(s => s.id !== song.id));
        
        // If deleted song was currently playing, stop it
        if (playerState.currentSong?.id === song.id) {
          audioManager.seek(0);
          if (playerState.isPlaying) {
            audioManager.togglePlay();
          }
        }

        toast(`Lagu "${song.title}" berhasil dihapus dari library!`, 'success');
        loadLocalDataAndSync();
      } catch (e: any) {
        toast('Gagal menghapus lagu: ' + e.message, 'error');
      }
  };

  // Rename song handler
  const handleRenameSongClick = (song: LocalSong) => {
    setSongToRename(song);
    setIsRenameOpen(true);
  };

  // Sync Cloud — download lagu baru dari Supabase Storage
  const handleSyncCloud = async () => {
    setSyncingCloud(true);
    try {
      await ensureMusicFolder();
      const count = await syncAllCloudMusic((msg) => {
        toast(msg, 'info');
      });
      if (count > 0) {
        toast(`✅ ${count} lagu berhasil didownload dari Cloud!`, 'success');
        loadLocalDataAndSync();
      } else {
        toast('Tidak ada lagu baru di Cloud.', 'info');
      }
    } catch (e: any) {
      toast('Sync Cloud gagal: ' + e.message, 'error');
    } finally {
      setSyncingCloud(false);
    }
  };

  // Delete all filtered songs
  const handleDeleteAll = async () => {
    const songsToDelete = getFilteredSongs();
    setIsDeleteAllOpen(false);
    try {
      for (const song of songsToDelete) {
        await deleteSong(song.id);
        if (favorites.includes(song.id)) {
          await toggleFavorite(song.id);
        }
      }
      setFavorites(prev => prev.filter(id => !songsToDelete.map(s => s.id).includes(id)));
      setLocalSongs(prev => prev.filter(s => !songsToDelete.map(s => s.id).includes(s.id)));
      if (songsToDelete.some(s => s.id === playerState.currentSong?.id)) {
        audioManager.seek(0);
        if (playerState.isPlaying) audioManager.togglePlay();
      }
      toast(`${songsToDelete.length} lagu berhasil dihapus!`, 'success');
      loadLocalDataAndSync();
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
    let filtered = [...allSongs];

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
    <div className="min-h-screen bg-[#0a0a0a] text-white flex flex-col pb-28 font-body">
      {/* Glow Header Background */}
      <div className="absolute top-0 left-0 right-0 h-48 bg-gradient-to-b from-[#c8f500]/5 to-transparent pointer-events-none"></div>

      {/* Header */}
      <header className="relative z-10 p-4 border-b border-white/5 bg-black/40 backdrop-blur-md sticky top-0 flex flex-col md:flex-row gap-4 items-center justify-between">
        {/* Logo */}
        <div className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-[#111] border border-[#c8f500]/20 shadow-[0_0_15px_rgba(200,245,0,0.1)]">
            <Disc className="w-6 h-6 text-[#c8f500] animate-spin-slow" />
          </div>
          <div>
            <h1 className="text-4xl font-heading text-[#c8f500] tracking-widest leading-none">KYOKOBEAT</h1>
            <p className="text-[9px] text-gray-500 uppercase tracking-widest mt-0.5">OFFLINE & CLOUD PLAYER</p>
          </div>
        </div>

        {/* Search & Cloud Actions */}
        <div className="flex flex-wrap items-center gap-3 w-full md:w-auto justify-end">
          {/* Help Button */}
          <button
            onClick={() => setShowHelp(!showHelp)}
            className="p-2 rounded-full bg-[#111] border border-gray-800 hover:border-[#c8f500]/40 text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer"
            title="Apa itu KyokoBeat?"
          >
            <HelpCircle className="w-4 h-4" />
          </button>

          {/* Search bar */}
          <div className="relative flex-1 sm:flex-initial min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
            <input
              type="text"
              placeholder="Cari lagu, artis, album..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-9 pr-4 py-2 bg-[#111] border border-[#c8f500]/10 rounded-full text-sm text-white placeholder-gray-500 focus:outline-none focus:border-[#c8f500] focus:shadow-[0_0_15px_rgba(200,245,0,0.1)] transition-all"
            />
          </div>

          {/* Cloud Sync Indicator */}
          <CloudSyncIndicator
            user={user}
            onLoginClick={() => setIsAuthOpen(true)}
            onLogoutSuccess={() => setUser(null)}
            favorites={favorites}
            playlists={playlists}
            onSyncComplete={loadLocalDataAndSync}
          />

          {/* Rescan Button */}
          <button
            onClick={handleRescan}
            disabled={scanning}
            className="p-2 px-3 rounded-full bg-[#111] border border-[#c8f500]/30 hover:border-[#c8f500] hover:bg-[#c8f500]/5 text-[#c8f500] text-xs font-semibold flex items-center gap-1.5 transition-all cursor-pointer"
          >
            {scanning ? (
              <>
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
                <span>Scanning...</span>
              </>
            ) : (
              <>
                <FolderSync className="w-3.5 h-3.5" />
                <span>Rescan Folder</span>
              </>
            )}
          </button>

          {/* Sync Cloud Button */}
          <button
            onClick={handleSyncCloud}
            disabled={syncingCloud}
            className="p-2 px-3 rounded-full bg-[#111] border border-blue-500/30 hover:border-blue-400 hover:bg-blue-500/5 text-blue-400 text-xs font-semibold flex items-center gap-1.5 transition-all cursor-pointer"
          >
            {syncingCloud ? (
              <>
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
                <span>Syncing...</span>
              </>
            ) : (
              <>
                <Cloud className="w-3.5 h-3.5" />
                <span>Sync Cloud</span>
              </>
            )}
          </button>
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
      <main className="flex-1 max-w-7xl w-full mx-auto p-4 grid grid-cols-1 lg:grid-cols-4 gap-6 relative z-10">
        {/* Left Side: Navigation / Playlists */}
        <div className="lg:col-span-1 space-y-6">
          {/* Library Tabs */}
          <div className="p-2 bg-[#111] rounded-xl border border-white/5 space-y-1">
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
                onClick={() => setIsDeleteAllOpen(true)}
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
                    <SongCard
                      key={song.id}
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
                    />
                  ))}
                </div>
              );
            })()}
          </div>
        </div>
      </main>

      {/* Bottom Player Bar */}
      {playerState.currentSong && (
        <div className="fixed bottom-0 left-0 right-0 bg-[#0a0a0a] border-t border-[#c8f500]/20 p-4 z-40 shadow-[0_-10px_30px_rgba(0,0,0,0.8)] backdrop-blur-lg">
          <div className="max-w-7xl w-full mx-auto flex flex-col md:flex-row gap-4 items-center justify-between">
            
            {/* Song Cover & Info */}
            <div className="flex items-center gap-4 w-full md:w-1/4 min-w-0">
              <div className="relative w-14 h-14 rounded-lg overflow-hidden bg-[#111] border border-white/5 flex-shrink-0 animate-spin-slow" style={{ animationPlayState: playerState.isPlaying ? 'running' : 'paused' }}>
                {playerState.currentSong.cover ? (
                  <img src={playerState.currentSong.cover} alt={playerState.currentSong.title} className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full flex items-center justify-center bg-[#151515] text-gray-600">
                    <Disc className="w-6 h-6 text-[#c8f500]" />
                  </div>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <h4 className="text-sm font-semibold truncate text-white">{playerState.currentSong.title}</h4>
                <p className="text-xs text-gray-400 truncate mt-0.5">{playerState.currentSong.artist}</p>
                
                {/* Waveform Visualizer */}
                <div className="mt-1 hidden sm:block">
                  <WaveformVisualizer isPlaying={playerState.isPlaying} />
                </div>
              </div>
            </div>

            {/* Player Controls & Seekbar */}
            <div className="flex flex-col items-center gap-2 w-full md:w-2/4">
              {/* Control Buttons */}
              <div className="flex items-center gap-4">
                {/* Shuffle */}
                <button
                  onClick={() => setShuffle(!shuffle)}
                  className={`p-2 transition-colors cursor-pointer ${shuffle ? 'text-[#c8f500]' : 'text-gray-500 hover:text-white'}`}
                  title="Acak Lagu"
                >
                  <Shuffle className="w-4 h-4" />
                </button>

                {/* Prev */}
                <button
                  onClick={playPrevTrack}
                  className="p-2 text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer"
                  title="Sebelumnya"
                >
                  <SkipBack className="w-5 h-5 fill-current" />
                </button>

                {/* Play/Pause */}
                <button
                  onClick={() => audioManager.togglePlay()}
                  className="p-3 bg-[#c8f500] hover:bg-[#b0dc00] text-black rounded-full shadow-[0_0_15px_rgba(200,245,0,0.3)] hover:shadow-[0_0_20px_rgba(200,245,0,0.5)] transition-all cursor-pointer"
                >
                  {playerState.isPlaying ? (
                    <Pause className="w-6 h-6 fill-current" />
                  ) : (
                    <Play className="w-6 h-6 fill-current ml-0.5" />
                  )}
                </button>

                {/* Next */}
                <button
                  onClick={playNextTrack}
                  className="p-2 text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer"
                  title="Berikutnya"
                >
                  <SkipForward className="w-5 h-5 fill-current" />
                </button>

                {/* Repeat */}
                <button
                  onClick={() => {
                    if (repeat === 'none') setRepeat('all');
                    else if (repeat === 'all') setRepeat('one');
                    else setRepeat('none');
                  }}
                  className={`p-2 transition-colors relative cursor-pointer ${repeat !== 'none' ? 'text-[#c8f500]' : 'text-gray-500 hover:text-white'}`}
                  title="Ulangi Lagu"
                >
                  <Repeat className="w-4 h-4" />
                  {repeat === 'one' && (
                    <span className="absolute bottom-0 right-0 bg-[#c8f500] text-black text-[7px] font-bold px-1 rounded-full scale-75">1</span>
                  )}
                </button>
              </div>

              {/* Seekbar */}
              <div className="flex items-center gap-3 w-full">
                <span className="text-[10px] text-gray-500 font-mono w-10 text-right">
                  {formatTime(playerState.currentTime)}
                </span>
                <input
                  type="range"
                  min="0"
                  max={playerState.duration || 100}
                  value={playerState.currentTime}
                  onChange={(e) => audioManager.seek(parseFloat(e.target.value))}
                  className="flex-1 h-1 bg-[#1a1a1a] rounded-full appearance-none cursor-pointer accent-[#c8f500] outline-none"
                />
                <span className="text-[10px] text-gray-500 font-mono w-10">
                  {formatTime(playerState.duration)}
                </span>
              </div>
            </div>

            {/* Volume Control */}
            <div className="flex items-center gap-3 w-full md:w-1/4 justify-end">
              <button
                onClick={() => audioManager.toggleMute()}
                className="p-2 text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer"
              >
                {playerState.isMuted || playerState.volume === 0 ? (
                  <VolumeX className="w-4 h-4" />
                ) : (
                  <Volume2 className="w-4 h-4" />
                )}
              </button>
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={playerState.isMuted ? 0 : playerState.volume}
                onChange={(e) => audioManager.setVolume(parseFloat(e.target.value))}
                className="w-20 sm:w-24 h-1 bg-[#1a1a1a] rounded-full appearance-none cursor-pointer accent-[#c8f500] outline-none"
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
        onConfirm={handleConfirmDelete}
        onCancel={() => {
          setIsDeleteOpen(false);
          setSongToDelete(null);
        }}
      />

      {/* Delete All Confirm Modal */}
      {isDeleteAllOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
          <div className="relative w-full max-w-sm p-6 rounded-xl bg-[#111] border border-red-500/30 shadow-[0_0_30px_rgba(239,68,68,0.15)]">
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center flex-shrink-0">
                <Trash2 className="w-5 h-5 text-red-400" />
              </div>
              <h3 className="text-xl font-heading text-white tracking-wider">HAPUS SEMUA</h3>
            </div>
            <p className="text-sm text-gray-400 font-body mb-1">
              Yakin hapus <span className="text-white font-semibold">{getFilteredSongs().length} lagu</span> dari filter "{
                durationFilter === 'under1' ? '< 1 menit' :
                durationFilter === '1to2' ? '1–2 menit' : '> 2 menit'
              }"?
            </p>
            <p className="text-xs text-red-400/70 font-body mb-6">Tindakan ini tidak bisa dibatalkan.</p>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={handleDeleteAll}
                className="flex-1 py-3 bg-red-500 text-white font-semibold rounded-lg hover:bg-red-600 transition-colors flex items-center justify-center gap-2 cursor-pointer text-sm"
              >
                <Trash2 className="w-4 h-4" /> Hapus Semua
              </button>
              <button
                type="button"
                onClick={() => setIsDeleteAllOpen(false)}
                className="flex-1 py-3 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg hover:bg-gray-900 transition-colors text-sm cursor-pointer"
              >
                Batal
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
