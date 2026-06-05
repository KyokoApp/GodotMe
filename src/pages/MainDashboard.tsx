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
  CloudDownload,
  Download,
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
import { checkFloatingPermission, requestFloatingPermission, showFloatingLyric, hideFloatingLyric } from '../lib/floatingLyrics';
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
import SoundCloudSearchModal from '../components/SoundCloudSearchModal';

import { useToast } from '../components/Toast';
import supabase from '../lib/supabase';

const DEFAULT_COVER = 'data:image/jpeg;base64,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';

// ── Circular Spectrum Player ──────────────────────────────────────────────────
function CircularSpectrumPlayer({ cover, title, isPlaying }: { cover: string | null; title: string; isPlaying: boolean }) {
  const BAR_COUNT = 60;
  const CX = 140, CY = 140, R_INNER = 88, R_MAX_BAR = 52;
  const smoothRef = React.useRef<Float32Array>(new Float32Array(BAR_COUNT).fill(2));
  const [bars, setBars] = React.useState<number[]>(new Array(BAR_COUNT).fill(2));
  const rafRef = React.useRef<number | null>(null);

  React.useEffect(() => {
    const tick = () => {
      rafRef.current = requestAnimationFrame(tick);
      const dataArray = audioManager.getAnalyserData();
      for (let i = 0; i < BAR_COUNT; i++) {
        let target: number;
        if (isPlaying && dataArray) {
          const bin = Math.floor((i / BAR_COUNT) * dataArray.length);
          target = (dataArray[bin] / 255) * R_MAX_BAR;
        } else {
          const t = Date.now() / 1200;
          target = 2 + 2 * Math.abs(Math.sin(t * 0.6 + i * 0.22));
        }
        const prev = smoothRef.current[i];
        smoothRef.current[i] = target > prev
          ? prev + (target - prev) * 0.4
          : prev + (target - prev) * 0.1;
      }
      setBars([...smoothRef.current]);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => { if (rafRef.current) cancelAnimationFrame(rafRef.current); };
  }, [isPlaying]);

  return (
    <div style={{ position: 'relative', width: 280, height: 280, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {/* SVG spectrum */}
      <svg width="280" height="280" viewBox="0 0 280 280" style={{ position: 'absolute', top: 0, left: 0 }}>
        {bars.map((h, i) => {
          const angle = (i / BAR_COUNT) * Math.PI * 2 - Math.PI / 2;
          const clamped = Math.max(2, Math.min(h, R_MAX_BAR));
          const x1 = CX + R_INNER * Math.cos(angle);
          const y1 = CY + R_INNER * Math.sin(angle);
          const x2 = CX + (R_INNER + clamped) * Math.cos(angle);
          const y2 = CY + (R_INNER + clamped) * Math.sin(angle);
          const t = clamped / R_MAX_BAR;
          const alpha = 0.3 + t * 0.7;
          return (
            <line
              key={i}
              x1={x1} y1={y1} x2={x2} y2={y2}
              stroke={`rgba(${Math.round(160 + t * 40)},${Math.round(230 + t * 15)},0,${alpha})`}
              strokeWidth={isPlaying && t > 0.65 ? 2.8 : 2}
              strokeLinecap="round"
            />
          );
        })}
        {/* subtle ring */}
        <circle cx={CX} cy={CY} r={R_INNER - 1} fill="none"
          stroke={isPlaying ? 'rgba(200,245,0,0.12)' : 'rgba(200,245,0,0.05)'}
          strokeWidth="1" />
      </svg>

      {/* Circular album art */}
      <div
        className={isPlaying ? 'kyoko-spinning' : ''}
        style={{
          width: 176, height: 176,
          borderRadius: '50%', overflow: 'hidden',
          border: '2px solid rgba(200,245,0,0.2)',
          boxShadow: isPlaying
            ? '0 0 0 5px rgba(200,245,0,0.05), 0 0 40px rgba(200,245,0,0.15)'
            : '0 0 30px rgba(0,0,0,0.6)',
          position: 'absolute', zIndex: 2,
          top: '50%', left: '50%',
          marginTop: -88, marginLeft: -88,
          background: '#111',
          transition: 'box-shadow 0.4s ease',
        }}
      >
        <img
          src={cover || DEFAULT_COVER}
          alt=""
          style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
          onError={(e) => {
            const img = e.target as HTMLImageElement;
            if (!img.dataset.retried) {
              img.dataset.retried = '1';
              img.src = 'https://raw.githubusercontent.com/Crashmant/rizky/main/uploads/1780465102494-416.jpeg';
            }
          }}
        />
      </div>
      <style>{`@keyframes kyokoSpin { to { transform: rotate(360deg); } } .kyoko-spinning { animation: kyokoSpin 22s linear infinite; }`}</style>
    </div>
  );
}
// ─────────────────────────────────────────────────────────────────────────────

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

  // Hardware back button handler (Android)
  useEffect(() => {
    let handler: any = null;
    const setup = async () => {
      try {
        const { App } = await import('@capacitor/app');
        handler = await App.addListener('backButton', ({ canGoBack }: { canGoBack: boolean }) => {
          if (showFullPlayer) {
            setShowFullPlayer(false);
          } else if (canGoBack) {
            window.history.back();
          } else {
            App.exitApp();
          }
        });
      } catch (e) {}
    };
    setup();
    return () => { handler?.remove(); };
  }, [showFullPlayer]);

  // ── LYRICS ──
  type LyricLine = { time: number; text: string };
  const [syncedLyrics, setSyncedLyrics] = useState<LyricLine[]>([]);
  const [plainLyrics, setPlainLyrics] = useState<string>('');
  const [lyricsLoading, setLyricsLoading] = useState(false);
  const [activeLyricIdx, setActiveLyricIdx] = useState(0);
  const [lyricsOffset, setLyricsOffset] = useState(0.5);
  const [floatingLyricsEnabled, setFloatingLyricsEnabled] = useState(false);
  const lyricsContainerRef = useRef<HTMLDivElement>(null);
  const lyricRefs = useRef<(HTMLParagraphElement | null)[]>([]);

  const OFFSET_KEY = (id: string) => `kyoko_lyric_offset_${id}`;

  const adjustOffset = (delta: number) => {
    const song = playerState.currentSong;
    if (!song) return;
    const next = Math.round((lyricsOffset + delta) * 10) / 10;
    setLyricsOffset(next);
    localStorage.setItem(OFFSET_KEY(song.id), String(next));
  };

  // ── FETCH LYRICS from LRCLIB (cloud songs only) ──
  useEffect(() => {
    const song = playerState.currentSong;
    setSyncedLyrics([]);
    setPlainLyrics('');
    setActiveLyricIdx(0);
    if (!song || !song.isCloud) return;
    // load saved offset for this song
    const saved = localStorage.getItem(OFFSET_KEY(song.id));
    setLyricsOffset(saved !== null ? parseFloat(saved) : 0.5);
    const title = song.title?.trim();
    const artist = song.artist?.trim();
    if (!title || title === 'Unknown Title') return;
    setLyricsLoading(true);
    const params = new URLSearchParams({ track_name: title });
    if (artist && artist !== 'Unknown Artist') params.set('artist_name', artist);
    fetch(`https://lrclib.net/api/search?${params}`)
      .then(r => r.json())
      .then((results: any[]) => {
        if (!results || results.length === 0) { setLyricsLoading(false); return; }
        const hit = results.find((r: any) => r.syncedLyrics) || results[0];
        if (hit?.syncedLyrics) {
          const lines: LyricLine[] = hit.syncedLyrics
            .split('\n')
            .map((line: string) => {
              const m = line.match(/^\[(\d+):(\d+\.\d+)\](.*)/);
              if (!m) return null;
              const time = parseInt(m[1]) * 60 + parseFloat(m[2]);
              return { time, text: m[3].trim() };
            })
            .filter(Boolean) as LyricLine[];
          setSyncedLyrics(lines);
        } else if (hit?.plainLyrics) {
          setPlainLyrics(hit.plainLyrics);
        }
        setLyricsLoading(false);
      })
      .catch(() => setLyricsLoading(false));
  }, [playerState.currentSong?.id]);

  // ── TRACK ACTIVE LYRIC LINE ──
  useEffect(() => {
    if (syncedLyrics.length === 0) return;
    const t = playerState.currentTime + lyricsOffset;
    let idx = 0;
    for (let i = 0; i < syncedLyrics.length; i++) {
      if (syncedLyrics[i].time <= t) idx = i;
      else break;
    }
    if (idx !== activeLyricIdx) {
      setActiveLyricIdx(idx);
      const el = lyricRefs.current[idx];
      if (el && lyricsContainerRef.current) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }
  }, [playerState.currentTime, syncedLyrics, lyricsOffset]);

  // ── PUSH ACTIVE LYRIC TO NATIVE FLOATING OVERLAY ──
  useEffect(() => {
    if (!floatingLyricsEnabled || !isCapacitorActive()) return;
    if (syncedLyrics.length === 0) return;
    const line = syncedLyrics[activeLyricIdx]?.text;
    if (line) showFloatingLyric(line);
  }, [activeLyricIdx, floatingLyricsEnabled]);

  // hide floating when disabled or song stops
  useEffect(() => {
    if (!floatingLyricsEnabled || !playerState.currentSong) {
      if (isCapacitorActive()) hideFloatingLyric();
    }
  }, [floatingLyricsEnabled, playerState.currentSong]);
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

  // YouTube Stream modal state
  const [isYtStreamOpen, setIsYtStreamOpen] = useState(false);
  const [ytStreamQuery, setYtStreamQuery] = useState('');
  const [ytStreamResults, setYtStreamResults] = useState<{id:string;title:string;author:string;thumb:string;duration:string}[]>([]);
  const [ytStreamLoading, setYtStreamLoading] = useState(false);
  const [ytStreamError, setYtStreamError] = useState('');

  // SoundCloud Search modal state
  const [isScModalOpen, setIsScModalOpen] = useState(false);

  // Dropdown states for compact filter UI
  const [showDurationDropdown, setShowDurationDropdown] = useState(false);
  const [showSortDropdown, setShowSortDropdown] = useState(false);
  const durationDropdownRef = useRef<HTMLDivElement>(null);
  const sortDropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdowns on outside mousedown (bukan capture click, biar tidak konflik dgn item onClick)
  useEffect(() => {
    if (!showDurationDropdown && !showSortDropdown) return;
    const handler = (e: MouseEvent) => {
      const target = e.target as Node;
      if (durationDropdownRef.current && !durationDropdownRef.current.contains(target)) {
        setShowDurationDropdown(false);
      }
      if (sortDropdownRef.current && !sortDropdownRef.current.contains(target)) {
        setShowSortDropdown(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [showDurationDropdown, showSortDropdown]);

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
      // PENTING: pertahankan title/artist/cover yang sudah di-rename/di-set dari DB
      const existingMap = new Map(currentSongs.map(s => [s.path, s]));
      const mergedScanned = songs.map(scanned => {
        const existing = existingMap.get(scanned.path);
        if (existing) {
          // Lagu sudah ada di DB — pakai metadata dari DB (bisa sudah di-rename/set cover)
          return {
            ...scanned,
            title: existing.title,
            artist: existing.artist,
            album: existing.album,
            cover: existing.cover ?? scanned.cover,
          };
        }
        return scanned;
      });
      const validDownloaded = existingDownloaded.filter(s => validCloudIds.has(s.id));
      // Tambahkan juga lagu SC/YT downloaded yang tidak ada validCloudIds-nya tapi punya cover
      const scYtDownloaded = currentSongs.filter(
        s => s.isDownloaded && (s.id.startsWith('sc-dl-') || s.id.startsWith('yt-dl-'))
      );
      const allDownloaded = [...validDownloaded, ...scYtDownloaded];
      const allSongsToSave = [...mergedScanned, ...allDownloaded];

      if (allSongsToSave.length !== currentSongs.length) {
        await clearSongs();
        await saveSongs(allSongsToSave);
        setLocalSongs(allSongsToSave);
        console.log(`[Auto-Sync Mobile] Updated library with ${allSongsToSave.length} songs.`);
      } else {
        // Jumlah sama tapi mungkin ada rename — tetap update DB biar rename tersimpan
        await clearSongs();
        await saveSongs(allSongsToSave);
        setLocalSongs(allSongsToSave);
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

      // Add new songs (lagu lama tidak disentuh — rename tetap aman)
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
        // Pertahankan title/artist/cover yang sudah di-rename dari DB
        const existingDb = await getSongs();
        const existingMap = new Map(existingDb.map(s => [s.path, s]));
        const merged = songs.map(scanned => {
          const existing = existingMap.get(scanned.path);
          if (existing) {
            // Preserve semua metadata yang sudah di-edit/di-set termasuk cover
            return { ...scanned, title: existing.title, artist: existing.artist, album: existing.album, cover: existing.cover ?? scanned.cover };
          }
          return scanned;
        });
        // Pertahankan juga lagu yang didownload dari cloud/YT/SC (tidak ada di scan)
        const downloadedSongs = existingDb.filter(s => s.isDownloaded && s.cover);
        const mergedPaths = new Set(merged.map(s => s.path));
        const extraDownloaded = downloadedSongs.filter(s => !mergedPaths.has(s.path));
        const finalSongs = [...merged, ...extraDownloaded];
        await clearSongs();
        await saveSongs(finalSongs);
        setLocalSongs(finalSongs);
        toast(`Berhasil mendeteksi ${merged.length} lagu dari HP Anda!`, 'success');
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
  // ── YOUTUBE STREAM ──
  const INVIDIOUS_INSTANCES = [
    'https://invidious.io.lol',
    'https://yt.artemislena.eu',
    'https://invidious.tiekoetter.com',
    'https://inv.riverside.rocks',
    'https://inv.nadeko.net',
    'https://invidious.privacydev.net',
  ];

  const PIPED_INSTANCES = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.tokhmi.xyz',
  ];

  const fetchWithTimeout = async (url: string, ms = 6000) => {
    const ctrl = new AbortController();
    const id = setTimeout(() => ctrl.abort(), ms);
    try {
      const res = await fetch(url, { signal: ctrl.signal });
      clearTimeout(id);
      return res;
    } catch (e) {
      clearTimeout(id);
      throw e;
    }
  };

  const ytStreamSearch = async () => {
    if (!ytStreamQuery.trim()) return;
    setYtStreamLoading(true);
    setYtStreamError('');
    setYtStreamResults([]);
    try {
      const res = await fetchWithTimeout(`https://api-faa.my.id/faa/youtube?q=${encodeURIComponent(ytStreamQuery)}`, 10000);
      if (!res.ok) throw new Error('API error');
      const data = await res.json();
      if (!data.status || !data.result?.length) throw new Error('Tidak ada hasil');
      const results = (data.result as any[]).slice(0, 10).map((v: any) => {
        const videoId = v.link?.split('watch?v=')[1] || '';
        return {
          id: videoId,
          title: v.title,
          author: v.channel,
          thumb: v.imageUrl || '',
          duration: v.duration || '',
          source: 'faa' as const,
        };
      }).filter((v: any) => v.id);
      setYtStreamResults(results);
    } catch (e: any) {
      setYtStreamError('Gagal mencari lagu. Coba lagi.');
    }
    setYtStreamLoading(false);
  };

  const [ytDownloadingId, setYtDownloadingId] = useState<string | null>(null);

  const ytStreamDownload = async (videoId: string, title: string, author: string, thumb: string) => {
    setYtDownloadingId(videoId);
    toast('⏳ Mengambil audio...', 'info');
    const result = await getAudioUrl(videoId);
    if (!result) {
      toast('Gagal download. Coba lagi.', 'error');
      setYtDownloadingId(null);
      return;
    }
    const audioUrl = result.url;
    const finalTitle = result.title || title;
    const finalThumb = result.thumb || thumb;
    toast(`⬇️ Mendownload "${finalTitle}"...`, 'info');
    try {
      const { Capacitor } = await import('@capacitor/core');
      const { Filesystem, Directory } = await import('@capacitor/filesystem');
      const { saveSong } = await import('../lib/db');
      if (Capacitor.isNativePlatform()) {
        const MUSIC_FOLDER = 'Android/media/com.kyokobeat.musicplayer/Music';
        try { await Filesystem.mkdir({ path: MUSIC_FOLDER, directory: Directory.ExternalStorage, recursive: true }); } catch (_) {}
        const audioRes = await fetch(audioUrl);
        const blob = await audioRes.blob();
        const base64 = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve((reader.result as string).split(',')[1]);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });
        const safeTitle = finalTitle.replace(/[^a-z0-9\s]/gi, '_').trim();
        const filePath = `${MUSIC_FOLDER}/${safeTitle}.mp3`;
        await Filesystem.writeFile({ path: filePath, data: base64, directory: Directory.ExternalStorage, recursive: true });
        const localUrl = Capacitor.convertFileSrc(`/storage/emulated/0/${filePath}`);
        await saveSong({ id: `yt-stream-dl-${videoId}`, title: finalTitle, artist: author || 'YouTube', album: 'YouTube Stream', duration: 0, cover: finalThumb || null, fileHandle: null as any, path: `/storage/emulated/0/${filePath}`, fileSize: blob.size, addedAt: Date.now(), isCloud: false, isDownloaded: false, audioUrl: localUrl });
      } else {
        await saveSong({ id: `yt-stream-dl-${videoId}`, title: finalTitle, artist: author || 'YouTube', album: 'YouTube Stream', duration: 0, cover: finalThumb || null, fileHandle: null as any, path: audioUrl, fileSize: 0, addedAt: Date.now(), isCloud: false, isDownloaded: true, audioUrl });
      }
      await loadLocalDataAndSync();
      toast(`✅ "${finalTitle}" tersimpan ke library!`, 'success');
    } catch {
      toast('Gagal download. Coba lagi.', 'error');
    }
    setYtDownloadingId(null);
  };

  const getAudioUrl = async (videoId: string): Promise<{url: string; title: string; thumb: string} | null> => {
    try {
      const ytUrl = `https://youtube.com/watch?v=${videoId}`;
      const res = await fetchWithTimeout(`/api/yt-download?url=${encodeURIComponent(ytUrl)}`, 15000);
      if (!res.ok) return null;
      const data = await res.json();
      if (!data.audioUrl) return null;
      return { url: data.audioUrl, title: data.title || '', thumb: data.thumbnail || '' };
    } catch {
      return null;
    }
  };

  const ytStreamPlay = async (videoId: string, title: string, author: string, thumb: string) => {
    setYtStreamLoading(true);
    toast('⏳ Memuat audio...', 'info');
    const result = await getAudioUrl(videoId);
    if (!result) {
      toast('Gagal load audio. Coba lagu lain.', 'error');
      setYtStreamLoading(false);
      return;
    }
    const streamSong: LocalSong = {
      id: `yt_stream_${videoId}`,
      title: result.title || title,
      artist: author,
      album: 'YouTube Stream',
      cover: result.thumb || thumb || null,
      path: result.url,
      audioUrl: result.url,
      isCloud: false,
      duration: 0,
      fileSize: 0,
      fileHandle: null as any,
      addedAt: Date.now(),
    };
    await handlePlaySong(streamSong);
    setIsYtStreamOpen(false);
    setYtStreamLoading(false);
  };

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

  // Rescan All — gabungan rescan folder lokal + refresh cloud dalam satu tombol
  const handleRescanAll = async () => {
    // Jalankan rescan folder lokal
    handleRescan();
    // Sekaligus refresh cloud
    setSyncingCloud(true);
    try {
      await loadCloudSongs();
    } catch (e) {
      console.warn('Cloud refresh during rescan failed:', e);
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

          {/* Right: icon-only action buttons — compact 3 icons */}
          <div className="flex items-center gap-1.5 flex-shrink-0">
            {/* Help */}
            <button
              onClick={() => setShowHelp(!showHelp)}
              title="Bantuan"
              className="w-8 h-8 rounded-full bg-[#111] border border-gray-800 hover:border-[#c8f500]/40 text-gray-500 hover:text-[#c8f500] transition-colors cursor-pointer flex items-center justify-center"
            >
              <HelpCircle className="w-3.5 h-3.5" />
            </button>

            {/* Cloud account — icon only (no username) */}
            <CloudSyncIndicator
              user={user}
              onLoginClick={() => setIsAuthOpen(true)}
              onLogoutSuccess={() => setUser(null)}
              favorites={favorites}
              playlists={playlists}
              onSyncComplete={loadLocalDataAndSync}
            />

            {/* Rescan gabungan (folder lokal + cloud) */}
            <button
              onClick={handleRescanAll}
              disabled={scanning || syncingCloud}
              title="Rescan Folder & Cloud"
              className="w-8 h-8 rounded-full bg-[#111] border border-[#c8f500]/30 hover:border-[#c8f500] text-[#c8f500] transition-all cursor-pointer flex items-center justify-center"
            >
              {(scanning || syncingCloud)
                ? <Loader2 className="w-3.5 h-3.5 animate-spin" />
                : <RefreshCw className="w-3.5 h-3.5" />}
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

          {/* Duration Filter + Sort + View + Download — compact 1 baris */}
          <div className="flex items-center gap-2 p-3 bg-[#111] rounded-xl border border-white/5">

            {/* Durasi Dropdown */}
            <div className="relative" ref={durationDropdownRef}>
              <button
                onClick={() => { setShowDurationDropdown(p => !p); setShowSortDropdown(false); }}
                className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-semibold border transition-all cursor-pointer ${
                  durationFilter !== 'all'
                    ? 'bg-[#c8f500]/10 border-[#c8f500]/40 text-[#c8f500]'
                    : 'bg-[#0a0a0a] border-gray-800 text-gray-400 hover:text-white'
                }`}
              >
                <span>⏱</span>
                <span>
                  {durationFilter === 'all' ? 'Durasi' :
                   durationFilter === 'under1' ? '< 1 mnt' :
                   durationFilter === '1to2' ? '1–2 mnt' : '> 2 mnt'}
                </span>
                <ChevronDown className={`w-3 h-3 transition-transform ${showDurationDropdown ? 'rotate-180' : ''}`} />
              </button>
              {showDurationDropdown && (
                <div className="absolute top-full left-0 mt-1 z-50 bg-[#1a1a1a] border border-gray-700/60 rounded-xl shadow-xl min-w-[160px] overflow-hidden animate-scale-up">
                  {([
                    { key: 'all', label: 'Semua Durasi' },
                    { key: 'under1', label: '< 1 menit' },
                    { key: '1to2', label: '1 – 2 menit' },
                    { key: 'over2', label: '> 2 menit' },
                  ] as const).map(({ key, label }) => (
                    <button
                      key={key}
                      onClick={() => { setDurationFilter(key); setShowDurationDropdown(false); }}
                      className={`w-full text-left px-3 py-2 text-xs font-semibold transition-colors cursor-pointer ${
                        durationFilter === key
                          ? 'text-[#c8f500] bg-[#c8f500]/10'
                          : 'text-gray-400 hover:text-white hover:bg-white/5'
                      }`}
                    >
                      {label}
                    </button>
                  ))}
                  {/* Hapus Semua di dalam dropdown kalau filter aktif */}
                  {durationFilter !== 'all' && (
                    <>
                      <div className="border-t border-gray-700/50 my-1" />
                      <button
                        onClick={() => { setIsDeleteAllOpen('choose'); setShowDurationDropdown(false); }}
                        className="w-full text-left px-3 py-2 text-xs font-semibold text-red-400 hover:bg-red-500/10 transition-colors cursor-pointer flex items-center gap-2"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                        Hapus Semua ({getFilteredSongs().filter(s => !s.isCloud).length})
                      </button>
                    </>
                  )}
                </div>
              )}
            </div>

            {/* Urutkan Dropdown */}
            <div className="relative" ref={sortDropdownRef}>
              <button
                onClick={() => { setShowSortDropdown(p => !p); setShowDurationDropdown(false); }}
                className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-semibold border bg-[#0a0a0a] border-gray-800 text-gray-400 hover:text-white transition-all cursor-pointer"
              >
                <SlidersHorizontal className="w-3 h-3" />
                <span>
                  {sortBy === 'title' ? 'Judul' : sortBy === 'artist' ? 'Artis' : 'Album'}
                  {sortOrder === 'asc' ? ' ↑' : ' ↓'}
                </span>
                <ChevronDown className={`w-3 h-3 transition-transform ${showSortDropdown ? 'rotate-180' : ''}`} />
              </button>
              {showSortDropdown && (
                <div className="absolute top-full left-0 mt-1 z-50 bg-[#1a1a1a] border border-gray-700/60 rounded-xl shadow-xl min-w-[150px] overflow-hidden animate-scale-up">
                  {(['title', 'artist', 'album'] as const).map((key) => (
                    <button
                      key={key}
                      onClick={() => {
                        if (sortBy === key) setSortOrder(o => o === 'asc' ? 'desc' : 'asc');
                        else { setSortBy(key); setSortOrder('asc'); }
                        setShowSortDropdown(false);
                      }}
                      className={`w-full text-left px-3 py-2 text-xs font-semibold transition-colors cursor-pointer flex items-center justify-between ${
                        sortBy === key
                          ? 'text-[#c8f500] bg-[#c8f500]/10'
                          : 'text-gray-400 hover:text-white hover:bg-white/5'
                      }`}
                    >
                      <span>{key === 'title' ? 'Judul' : key === 'artist' ? 'Artis' : 'Album'}</span>
                      {sortBy === key && <ArrowUpDown className="w-3 h-3" />}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Spacer */}
            <div className="flex-1" />

            {/* View mode: grid / list */}
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

          {/* Download buttons: Cari Lagu + YouTube Download + YouTube Stream */}
          <div className="grid grid-cols-3 gap-2">
            <button
              onClick={() => setIsScModalOpen(true)}
              title="Cari Lagu Online"
              className="flex items-center justify-center gap-1.5 px-2 py-2 rounded-lg bg-[#c8f500] hover:bg-[#d4ff00] text-black text-xs font-bold transition-all cursor-pointer shadow-[0_0_12px_rgba(200,245,0,0.3)] hover:shadow-[0_0_18px_rgba(200,245,0,0.5)] active:scale-95"
            >
              <CloudDownload className="w-3.5 h-3.5" />
              Cari Lagu
            </button>
            <button
              onClick={() => setIsYtModalOpen(true)}
              title="Download dari YouTube"
              className="flex items-center justify-center gap-1.5 px-2 py-2 rounded-lg bg-red-500/15 border border-red-500/40 hover:border-red-500 hover:bg-red-500/25 text-red-400 text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              <Youtube className="w-3.5 h-3.5" />
              YT Download
            </button>
            <button
              onClick={() => setIsYtStreamOpen(true)}
              title="Stream dari YouTube"
              className="flex items-center justify-center gap-1.5 px-2 py-2 rounded-lg bg-orange-500/15 border border-orange-500/40 hover:border-orange-500 hover:bg-orange-500/25 text-orange-400 text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              <Play className="w-3.5 h-3.5" />
              YT Stream
            </button>
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
                    <div className="flex flex-col gap-1">
                      {playlists.map((pl) => (
                        <div
                          key={pl.id}
                          className="flex items-center gap-3 px-3 py-2.5 rounded-lg bg-[#111] border border-white/5 hover:border-[#c8f500]/20 hover:bg-[#161616] transition-all group"
                        >
                          <FolderHeart className="w-4 h-4 text-[#c8f500] flex-shrink-0" />
                          <div
                            className="flex-1 min-w-0 cursor-pointer"
                            onClick={() => setSelectedPlaylistId(pl.id)}
                          >
                            <p className="text-sm font-semibold truncate">{pl.name}</p>
                            <p className="text-[10px] text-gray-500">{pl.songIds.length} Lagu</p>
                          </div>
                          <button
                            onClick={() => handleDeletePlaylist(pl.id, pl.name)}
                            className="opacity-0 group-hover:opacity-100 px-2 py-1 border border-red-500/20 text-red-400 hover:bg-red-500/10 text-[10px] font-bold rounded cursor-pointer transition-opacity"
                          >
                            Hapus
                          </button>
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

          {/* Album art + Circular Spectrum + song info */}
          <div className="flex-1 flex flex-col items-center justify-center px-8 gap-4 min-h-0">

            {/* ── LYRICS SECTION (cloud only) ── */}
            {playerState.currentSong.isCloud && (
              <div
                ref={lyricsContainerRef}
                className="w-full max-h-[180px] overflow-y-auto text-center px-2 scrollbar-none"
                style={{ maskImage: 'linear-gradient(to bottom, transparent 0%, black 18%, black 82%, transparent 100%)', WebkitMaskImage: 'linear-gradient(to bottom, transparent 0%, black 18%, black 82%, transparent 100%)' }}
              >
                {lyricsLoading ? (
                  <p className="text-xs text-gray-600 animate-pulse py-4">Mencari lirik...</p>
                ) : syncedLyrics.length > 0 ? (
                  <div className="py-10 space-y-3">
                    {syncedLyrics.map((line, i) => (
                      <p
                        key={i}
                        ref={el => { lyricRefs.current[i] = el; }}
                        className="transition-all duration-300 leading-snug"
                        style={{
                          fontSize: i === activeLyricIdx ? '15px' : '13px',
                          fontWeight: i === activeLyricIdx ? 700 : 400,
                          color: i === activeLyricIdx ? '#c8f500' : 'rgba(255,255,255,0.25)',
                          transform: i === activeLyricIdx ? 'scale(1.04)' : 'scale(1)',
                        }}
                      >
                        {line.text || '·'}
                      </p>
                    ))}
                  </div>
                ) : plainLyrics ? (
                  <div className="py-4 space-y-2">
                    {plainLyrics.split('\n').map((line, i) => (
                      <p key={i} className="text-xs text-gray-500 leading-snug">{line || ' '}</p>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-gray-700 py-4">Lirik tidak tersedia</p>
                )}
              </div>
            )}

            {/* Offset adjuster — only when synced lyrics exist */}
            {playerState.currentSong.isCloud && syncedLyrics.length > 0 && (
              <div className="flex items-center gap-3">
                <button
                  onClick={() => adjustOffset(-0.5)}
                  className="w-7 h-7 rounded-full bg-white/5 border border-white/10 text-white text-sm font-bold flex items-center justify-center active:scale-90 cursor-pointer"
                >−</button>
                <span className="text-[10px] text-gray-500 w-20 text-center">
                  {lyricsOffset >= 0 ? `+${lyricsOffset.toFixed(1)}` : lyricsOffset.toFixed(1)}s
                </span>
                <button
                  onClick={() => adjustOffset(0.5)}
                  className="w-7 h-7 rounded-full bg-white/5 border border-white/10 text-white text-sm font-bold flex items-center justify-center active:scale-90 cursor-pointer"
                >+</button>

                {/* Floating lyrics toggle */}
                <button
                  onClick={async (e) => {
                    e.stopPropagation();
                    if (!floatingLyricsEnabled) {
                      const granted = await checkFloatingPermission();
                      if (!granted) {
                        await requestFloatingPermission();
                        return;
                      }
                    }
                    setFloatingLyricsEnabled(v => !v);
                  }}
                  className={`ml-2 px-2.5 py-1 rounded-full text-[10px] font-bold border transition-all cursor-pointer ${
                    floatingLyricsEnabled
                      ? 'bg-[#c8f500]/15 border-[#c8f500]/50 text-[#c8f500]'
                      : 'bg-white/5 border-white/10 text-gray-500'
                  }`}
                >
                  {floatingLyricsEnabled ? '📌 Float ON' : '📌 Float'}
                </button>
              </div>
            )}

            <CircularSpectrumPlayer
              cover={playerState.currentSong.cover ?? null}
              title={playerState.currentSong.title}
              isPlaying={playerState.isPlaying}
            />
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

      {/* SoundCloud Search Modal */}
      <SoundCloudSearchModal
        isOpen={isScModalOpen}
        onClose={() => setIsScModalOpen(false)}
        onDownloadComplete={() => {
          loadLocalDataAndSync();
          setSourceFilter('offline');
        }}
        toast={toast}
      />

      {/* ── YOUTUBE STREAM MODAL ── */}
      {isYtStreamOpen && (
        <div className="fixed inset-0 z-[200] flex flex-col bg-[#0a0a0a]">
          {/* Header */}
          <div className="flex items-center gap-3 px-4 pt-12 pb-4 border-b border-white/5">
            <button onClick={() => setIsYtStreamOpen(false)} className="p-2 text-gray-400 cursor-pointer">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M19 12H5M12 5l-7 7 7 7"/></svg>
            </button>
            <div>
              <h2 className="text-base font-bold text-white">YouTube Stream</h2>
              <p className="text-[10px] text-gray-500">Putar langsung, tidak tersimpan</p>
            </div>
          </div>

          {/* Search bar */}
          <div className="px-4 py-3 flex gap-2">
            <input
              value={ytStreamQuery}
              onChange={e => setYtStreamQuery(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && ytStreamSearch()}
              placeholder="Cari judul, artis, album..."
              className="flex-1 bg-[#111] border border-white/10 rounded-lg px-3 py-2.5 text-sm text-white placeholder-gray-600 outline-none focus:border-orange-400/50"
              autoFocus
            />
            <button
              onClick={ytStreamSearch}
              disabled={ytStreamLoading}
              className="px-4 py-2.5 bg-orange-500/20 border border-orange-500/40 text-orange-400 text-xs font-bold rounded-lg cursor-pointer active:scale-95 disabled:opacity-50"
            >
              {ytStreamLoading ? '...' : 'Cari'}
            </button>
          </div>

          {/* Error */}
          {ytStreamError && (
            <p className="px-4 text-xs text-red-400">{ytStreamError}</p>
          )}

          {/* Results */}
          <div className="flex-1 overflow-y-auto px-4 pb-24">
            {ytStreamResults.length === 0 && !ytStreamLoading && !ytStreamError && (
              <div className="flex flex-col items-center justify-center h-48 gap-2">
                <Youtube className="w-10 h-10 text-orange-500/30" />
                <p className="text-xs text-gray-600">Cari lagu untuk diputar langsung</p>
              </div>
            )}
            {ytStreamResults.map(v => (
              <div
                key={v.id}
                className="w-full flex items-center gap-3 p-3 mb-2 rounded-xl bg-[#111] border border-white/5 hover:border-orange-400/20 transition-all"
              >
                {v.thumb ? (
                  <img src={v.thumb} alt="" className="w-14 h-14 rounded-lg object-cover flex-shrink-0 bg-[#1a1a1a]" />
                ) : (
                  <div className="w-14 h-14 rounded-lg bg-[#1a1a1a] flex items-center justify-center flex-shrink-0">
                    <Youtube className="w-5 h-5 text-orange-500/40" />
                  </div>
                )}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold truncate text-white">{v.title}</p>
                  <p className="text-xs text-gray-500 truncate mt-0.5">{v.author}</p>
                  <p className="text-[10px] text-orange-400/60 mt-1">{v.duration}</p>
                </div>
                {/* Play button */}
                <button
                  onClick={() => ytStreamPlay(v.id, v.title, v.author, v.thumb)}
                  disabled={ytStreamLoading}
                  className="p-2 rounded-full bg-orange-500/15 border border-orange-500/30 text-orange-400 active:scale-90 cursor-pointer disabled:opacity-40"
                  title="Putar"
                >
                  <Play className="w-4 h-4" />
                </button>
                {/* Download button */}
                <button
                  onClick={() => ytStreamDownload(v.id, v.title, v.author, v.thumb)}
                  disabled={ytDownloadingId === v.id}
                  className="p-2 rounded-full bg-[#c8f500]/10 border border-[#c8f500]/30 text-[#c8f500] active:scale-90 cursor-pointer disabled:opacity-40"
                  title="Download ke device"
                >
                  {ytDownloadingId === v.id
                    ? <div className="w-4 h-4 border-2 border-[#c8f500]/40 border-t-[#c8f500] rounded-full animate-spin" />
                    : <Download className="w-4 h-4" />
                  }
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

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
