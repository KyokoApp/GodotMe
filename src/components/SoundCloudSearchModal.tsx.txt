import React, { useState, useRef, useEffect } from 'react';
import { X, Search, Download, Loader2, Music, CheckCircle, CloudDownload, Play, Pause, Volume2 } from 'lucide-react';

interface SoundCloudSearchModalProps {
  isOpen: boolean;
  onClose: () => void;
  onDownloadComplete: () => void;
  toast: (msg: string, type: 'success' | 'error' | 'info') => void;
}

interface SCResult {
  url: string;
  title: string;
  user: string;
  thumbnail: string;
}

const SC_API_URL = 'https://api-faa.my.id/faa/soundcloud-play';

export default function SoundCloudSearchModal({
  isOpen,
  onClose,
  onDownloadComplete,
  toast,
}: SoundCloudSearchModalProps) {
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [result, setResult] = useState<SCResult | null>(null);
  const [error, setError] = useState('');
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [downloadedTitles, setDownloadedTitles] = useState<Set<string>>(new Set());
  const inputRef = useRef<HTMLInputElement>(null);

  // Preview player state
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [previewProgress, setPreviewProgress] = useState(0);
  const [previewDuration, setPreviewDuration] = useState(0);
  const [previewLoading, setPreviewLoading] = useState(false);

  // Cleanup audio on close / unmount
  useEffect(() => {
    return () => {
      audioRef.current?.pause();
    };
  }, []);

  const stopPreview = () => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
    }
    setIsPlaying(false);
    setPreviewProgress(0);
    setPreviewDuration(0);
  };

  const togglePreview = (url: string) => {
    if (!audioRef.current) {
      audioRef.current = new Audio();
      audioRef.current.ontimeupdate = () => {
        setPreviewProgress(audioRef.current?.currentTime || 0);
      };
      audioRef.current.onloadedmetadata = () => {
        setPreviewDuration(audioRef.current?.duration || 0);
        setPreviewLoading(false);
      };
      audioRef.current.onended = () => {
        setIsPlaying(false);
        setPreviewProgress(0);
      };
      audioRef.current.onerror = () => {
        setPreviewLoading(false);
        setIsPlaying(false);
      };
    }

    if (isPlaying) {
      audioRef.current.pause();
      setIsPlaying(false);
    } else {
      if (audioRef.current.src !== url) {
        audioRef.current.src = url;
        setPreviewProgress(0);
        setPreviewDuration(0);
        setPreviewLoading(true);
      }
      audioRef.current.play().then(() => setIsPlaying(true)).catch(() => setPreviewLoading(false));
    }
  };

  const handleSeek = (e: React.ChangeEvent<HTMLInputElement>) => {
    const t = parseFloat(e.target.value);
    if (audioRef.current) {
      audioRef.current.currentTime = t;
      setPreviewProgress(t);
    }
  };

  const formatTime = (s: number) => {
    if (!s || isNaN(s)) return '0:00';
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  if (!isOpen) return null;

  const handleSearch = async () => {
    if (!query.trim()) return;
    setSearching(true);
    setResult(null);
    setError('');

    try {
      const res = await fetch(`${SC_API_URL}?query=${encodeURIComponent(query.trim())}`);
      if (!res.ok) throw new Error('API error');
      const data = await res.json();

      if (data?.status === false || !data?.result) {
        throw new Error(data?.message || 'Lagu tidak ditemukan');
      }

      const r = data.result;
      setResult({
        url: r.download_url || '',
        title: r.title || query,
        user: r.user || r.artist || 'Unknown Artist',
        thumbnail: r.thumbnail || '',
      });
    } catch (e: any) {
      setError('Lagu tidak ditemukan atau API sedang bermasalah.');
    } finally {
      setSearching(false);
    }
  };

  const handleDownload = async (track: SCResult) => {
    const dlKey = track.title;
    setDownloadingId(dlKey);
    setError('');

    try {
      const { saveSong } = await import('../lib/db');
      const isNative =
        typeof window !== 'undefined' &&
        (window as any).Capacitor?.isNativePlatform?.();

      if (isNative) {
        const { Filesystem, Directory } = await import('@capacitor/filesystem');
        const { Capacitor } = await import('@capacitor/core');

        const MUSIC_FOLDER = 'Android/media/com.kyokobeat.musicplayer/Music';

        try {
          await Filesystem.mkdir({
            path: MUSIC_FOLDER,
            directory: Directory.ExternalStorage,
            recursive: true,
          });
        } catch (_) {}

        const audioRes = await fetch(track.url);
        const blob = await audioRes.blob();

        const base64 = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve((reader.result as string).split(',')[1]);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });

        const safeTitle = track.title.replace(/[^a-z0-9\s]/gi, '_').trim();
        const fileName = `${safeTitle}.mp3`;
        const filePath = `${MUSIC_FOLDER}/${fileName}`;

        await Filesystem.writeFile({
          path: filePath,
          data: base64,
          directory: Directory.ExternalStorage,
          recursive: true,
        });

        const localUrl = Capacitor.convertFileSrc(`/storage/emulated/0/${filePath}`);

        await saveSong({
          id: `sc-dl-${Date.now()}`,
          title: track.title,
          artist: track.user || 'SoundCloud',
          album: 'SoundCloud',
          duration: 0,
          cover: track.thumbnail || null,
          fileHandle: null as any,
          path: `/storage/emulated/0/${filePath}`,
          fileSize: blob.size,
          addedAt: Date.now(),
          isCloud: false,
          isDownloaded: false,
          audioUrl: localUrl,
        });
      } else {
        // Web fallback — simpan URL langsung
        await saveSong({
          id: `sc-dl-${Date.now()}`,
          title: track.title,
          artist: track.user || 'SoundCloud',
          album: 'SoundCloud',
          duration: 0,
          cover: track.thumbnail || null,
          fileHandle: null as any,
          path: track.url,
          fileSize: 0,
          addedAt: Date.now(),
          isCloud: false,
          isDownloaded: true,
          audioUrl: track.url,
        });
      }

      setDownloadedTitles((prev) => new Set([...prev, dlKey]));
      toast(`✅ "${track.title}" berhasil disimpan ke offline!`, 'success');
      onDownloadComplete();
    } catch (e: any) {
      setError('Gagal mendownload lagu. Coba lagi.');
      toast('❌ Gagal mendownload lagu.', 'error');
    } finally {
      setDownloadingId(null);
    }
  };

  const handleClose = () => {
    stopPreview();
    setQuery('');
    setResult(null);
    setError('');
    setSearching(false);
    onClose();
  };

  const isDownloaded = result ? downloadedTitles.has(result.title) : false;
  const isDownloading = result ? downloadingId === result.title : false;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <div className="relative w-full max-w-sm rounded-xl bg-[#111] border border-[#c8f500]/20 shadow-[0_0_40px_rgba(200,245,0,0.08)] animate-scale-up">

        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-white/5">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-[#c8f500]/10 border border-[#c8f500]/20">
              <Music className="w-5 h-5 text-[#c8f500]" />
            </div>
            <div>
              <h3 className="text-sm font-bold text-white">Cari Lagu Online</h3>
              <p className="text-[10px] text-gray-500">Cari & download lagu via SoundCloud</p>
            </div>
          </div>
          <button
            onClick={handleClose}
            className="p-1.5 text-gray-500 hover:text-white transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Body */}
        <div className="p-5 space-y-4">

          {/* Search Input */}
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-500" />
              <input
                ref={inputRef}
                type="text"
                placeholder="Ketik judul lagu..."
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setError('');
                }}
                onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
                className="w-full pl-8 pr-3 py-2.5 bg-[#0a0a0a] border border-white/10 rounded-lg text-xs text-white placeholder-gray-600 focus:outline-none focus:border-[#c8f500]/50 transition-all"
              />
            </div>
            <button
              onClick={handleSearch}
              disabled={searching || !query.trim()}
              className="px-3 py-2.5 bg-[#c8f500] hover:bg-[#b8e000] disabled:opacity-40 disabled:cursor-not-allowed text-black rounded-lg text-xs font-bold flex items-center gap-1.5 transition-colors cursor-pointer flex-shrink-0"
            >
              {searching ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Search className="w-3.5 h-3.5" />
              )}
            </button>
          </div>

          {/* Error */}
          {error && (
            <p className="text-[10px] text-red-400 px-1">{error}</p>
          )}

          {/* Searching state */}
          {searching && (
            <div className="flex items-center gap-3 p-3 bg-[#0a0a0a] rounded-lg border border-[#c8f500]/10">
              <Loader2 className="w-4 h-4 text-[#c8f500] animate-spin flex-shrink-0" />
              <p className="text-xs text-gray-400">Mencari lagu di SoundCloud...</p>
            </div>
          )}

          {/* Result Card */}
          {result && !searching && (
            <div className="bg-[#0a0a0a] rounded-lg border border-white/5 overflow-hidden">
              {/* Track info row */}
              <div className="flex items-center gap-3 p-3">
                {result.thumbnail ? (
                  <img
                    src={result.thumbnail}
                    alt={result.title}
                    className="w-12 h-12 rounded-lg object-cover flex-shrink-0"
                  />
                ) : (
                  <div className="w-12 h-12 rounded-lg bg-[#1a1a1a] flex items-center justify-center flex-shrink-0">
                    <Music className="w-5 h-5 text-gray-600" />
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-semibold text-white truncate">{result.title}</p>
                  <p className="text-[10px] text-gray-500 mt-0.5 truncate">{result.user}</p>
                  <p className="text-[9px] text-[#c8f500]/50 mt-0.5">SoundCloud</p>
                </div>
              </div>

              {/* Preview Player */}
              <div className="px-3 pb-2">
                <div className="bg-[#111] rounded-lg border border-white/5 p-2.5">
                  {/* Play/Pause + Progress */}
                  <div className="flex items-center gap-2.5">
                    <button
                      onClick={() => togglePreview(result.url)}
                      disabled={previewLoading}
                      className="w-8 h-8 rounded-full bg-[#c8f500] hover:bg-[#d4ff00] disabled:opacity-50 flex items-center justify-center flex-shrink-0 transition-all active:scale-95 cursor-pointer shadow-[0_0_10px_rgba(200,245,0,0.3)]"
                    >
                      {previewLoading ? (
                        <Loader2 className="w-3.5 h-3.5 text-black animate-spin" />
                      ) : isPlaying ? (
                        <Pause className="w-3.5 h-3.5 text-black fill-black" />
                      ) : (
                        <Play className="w-3.5 h-3.5 text-black fill-black ml-0.5" />
                      )}
                    </button>

                    <div className="flex-1 space-y-1">
                      <input
                        type="range"
                        min={0}
                        max={previewDuration || 100}
                        value={previewProgress}
                        onChange={handleSeek}
                        className="w-full h-1 rounded-full appearance-none cursor-pointer outline-none"
                        style={{
                          background: `linear-gradient(to right, #c8f500 ${previewDuration ? (previewProgress / previewDuration) * 100 : 0}%, rgba(255,255,255,0.1) 0%)`
                        }}
                      />
                      <div className="flex justify-between">
                        <span className="text-[9px] text-gray-600 font-mono">{formatTime(previewProgress)}</span>
                        <span className="text-[9px] text-gray-600 font-mono">{formatTime(previewDuration)}</span>
                      </div>
                    </div>

                    <Volume2 className="w-3.5 h-3.5 text-gray-600 flex-shrink-0" />
                  </div>

                  <p className="text-[9px] text-gray-600 text-center mt-1">
                    {isPlaying ? '▶ Preview sedang diputar' : 'Tap play untuk preview sebelum download'}
                  </p>
                </div>
              </div>

              {/* Download button inside card */}
              <div className="px-3 pb-3">
                {isDownloaded ? (
                  <div className="flex items-center gap-2 py-2 px-3 bg-green-500/5 rounded-lg border border-green-500/20">
                    <CheckCircle className="w-3.5 h-3.5 text-green-400" />
                    <span className="text-[10px] text-green-300 font-semibold">Tersimpan di Offline</span>
                  </div>
                ) : (
                  <button
                    onClick={() => handleDownload(result)}
                    disabled={isDownloading}
                    className="w-full py-2 bg-[#c8f500]/10 hover:bg-[#c8f500]/20 border border-[#c8f500]/30 hover:border-[#c8f500]/60 disabled:opacity-40 disabled:cursor-not-allowed text-[#c8f500] rounded-lg text-xs font-bold flex items-center justify-center gap-2 transition-all cursor-pointer"
                  >
                    {isDownloading ? (
                      <>
                        <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        Menyimpan...
                      </>
                    ) : (
                      <>
                        <CloudDownload className="w-3.5 h-3.5" />
                        Download ke Offline
                      </>
                    )}
                  </button>
                )}
              </div>
            </div>
          )}

          {/* Empty state */}
          {!result && !searching && !error && (
            <div className="flex flex-col items-center gap-2 py-6 text-center">
              <div className="w-10 h-10 rounded-full bg-[#c8f500]/5 border border-[#c8f500]/10 flex items-center justify-center">
                <Music className="w-5 h-5 text-[#c8f500]/30" />
              </div>
              <p className="text-[11px] text-gray-600">
                Ketik judul lagu lalu tekan Enter atau tombol cari
              </p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 pb-5">
          <button
            onClick={handleClose}
            className="w-full py-2.5 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg text-xs font-semibold transition-colors cursor-pointer"
          >
            Tutup
          </button>
        </div>
      </div>
    </div>
  );
}
