import React, { useState } from 'react';
import { X, Youtube, Download, Loader2, Music, CheckCircle } from 'lucide-react';

interface YtDownloadModalProps {
  isOpen: boolean;
  onClose: () => void;
  onDownloadComplete: () => void;
  toast: (msg: string, type: 'success' | 'error' | 'info') => void;
}

type Status = 'idle' | 'fetching' | 'downloading' | 'done' | 'error';

export default function YtDownloadModal({ isOpen, onClose, onDownloadComplete, toast }: YtDownloadModalProps) {
  const [url, setUrl] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [progress, setProgress] = useState('');
  const [songInfo, setSongInfo] = useState<{ title: string; thumbnail: string | null } | null>(null);
  const [error, setError] = useState('');

  if (!isOpen) return null;

  const isYouTubeUrl = (u: string) =>
    /^https?:\/\/(www\.)?(youtube\.com\/(watch\?v=|shorts\/|music)|youtu\.be\/)/.test(u.trim());

  const handleDownload = async () => {
    const trimmed = url.trim();
    if (!trimmed) return;

    if (!isYouTubeUrl(trimmed)) {
      setError('URL tidak valid. Pastikan link dari YouTube.');
      return;
    }

    setError('');
    setStatus('fetching');
    setProgress('Mengambil info lagu dari YouTube...');
    setSongInfo(null);

    try {
      // Step 1: Fetch audio URL dari api-faa
      const res = await fetch(`https://api-faa.my.id/faa/ytmp3?url=${encodeURIComponent(trimmed)}`);
      const data = await res.json();

      if (!res.ok || !data.status || !data.result?.mp3) {
        throw new Error(data.error || 'Gagal mendapatkan audio dari YouTube');
      }

      // Normalize response ke format yang dipakai di bawah
      data.audioUrl = data.result.mp3;
      data.title = data.result.title;
      data.thumbnail = data.result.thumbnail;

      setSongInfo({ title: data.title, thumbnail: data.thumbnail });
      setStatus('downloading');
      setProgress(`Mengunduh "${data.title}"...`);

      // Step 2: Download file audio ke HP
      const isNative = typeof window !== 'undefined' && (window as any).Capacitor?.isNativePlatform?.();

      if (isNative) {
        // Native: download via Capacitor Filesystem
        const { Filesystem, Directory } = await import('@capacitor/filesystem');
        const { Capacitor } = await import('@capacitor/core');

        const MUSIC_FOLDER = 'Android/media/com.kyokobeat.musicplayer/Music';

        // Ensure folder exists
        try {
          await Filesystem.mkdir({ path: MUSIC_FOLDER, directory: Directory.ExternalStorage, recursive: true });
        } catch (_) {}

        setProgress(`Mendownload file audio...`);
        const audioRes = await fetch(data.audioUrl);
        const blob = await audioRes.blob();

        // Convert blob to base64
        const base64 = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve((reader.result as string).split(',')[1]);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });

        const safeTitle = data.title.replace(/[^a-z0-9\s]/gi, '_').trim();
        const fileName = `${safeTitle}.mp3`;
        const filePath = `${MUSIC_FOLDER}/${fileName}`;

        await Filesystem.writeFile({
          path: filePath,
          data: base64,
          directory: Directory.ExternalStorage,
          recursive: true,
        });

        setProgress('Menyimpan ke library...');

        // Save to IndexedDB
        const { saveSong } = await import('../lib/db');
        const localUrl = Capacitor.convertFileSrc(`/storage/emulated/0/${filePath}`);
        await saveSong({
          id: `yt-dl-${Date.now()}`,
          title: data.title,
          artist: 'YouTube Download',
          album: 'YouTube',
          duration: data.duration || 0,
          cover: data.thumbnail || null,
          fileHandle: null as any,
          path: `/storage/emulated/0/${filePath}`,
          fileSize: blob.size,
          addedAt: Date.now(),
          isCloud: false,
          isDownloaded: false,
          audioUrl: localUrl,
        });

      } else {
        // Web fallback: simpan sebagai referensi URL langsung
        const { saveSong } = await import('../lib/db');
        await saveSong({
          id: `yt-dl-${Date.now()}`,
          title: data.title,
          artist: 'YouTube Download',
          album: 'YouTube',
          duration: data.duration || 0,
          cover: data.thumbnail || null,
          fileHandle: null as any,
          path: data.audioUrl,
          fileSize: 0,
          addedAt: Date.now(),
          isCloud: false,
          isDownloaded: true,
          audioUrl: data.audioUrl,
        });
      }

      setStatus('done');
      setProgress('');
      toast(`✅ "${data.title}" berhasil diunduh!`, 'success');
      onDownloadComplete();

    } catch (e: any) {
      console.error('YT Download error:', e);
      setStatus('error');
      setError(e.message || 'Terjadi kesalahan saat mengunduh');
      setProgress('');
    }
  };

  const handleClose = () => {
    if (status === 'fetching' || status === 'downloading') return;
    setUrl('');
    setStatus('idle');
    setProgress('');
    setSongInfo(null);
    setError('');
    onClose();
  };

  const handleReset = () => {
    setUrl('');
    setStatus('idle');
    setProgress('');
    setSongInfo(null);
    setError('');
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <div className="relative w-full max-w-sm rounded-xl bg-[#111] border border-red-500/20 shadow-[0_0_40px_rgba(239,68,68,0.1)] animate-scale-up">

        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-white/5">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-red-500/10 border border-red-500/20">
              <Youtube className="w-5 h-5 text-red-500" />
            </div>
            <div>
              <h3 className="text-sm font-bold text-white">Download YouTube</h3>
              <p className="text-[10px] text-gray-500">Paste link YouTube, download jadi audio</p>
            </div>
          </div>
          <button
            onClick={handleClose}
            disabled={status === 'fetching' || status === 'downloading'}
            className="p-1.5 text-gray-500 hover:text-white transition-colors disabled:opacity-30"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Body */}
        <div className="p-5 space-y-4">

          {/* Song info preview */}
          {songInfo && (
            <div className="flex items-center gap-3 p-3 bg-[#0a0a0a] rounded-lg border border-white/5">
              {songInfo.thumbnail ? (
                <img src={songInfo.thumbnail} alt={songInfo.title} className="w-12 h-12 rounded-lg object-cover flex-shrink-0" />
              ) : (
                <div className="w-12 h-12 rounded-lg bg-[#1a1a1a] flex items-center justify-center flex-shrink-0">
                  <Music className="w-5 h-5 text-gray-600" />
                </div>
              )}
              <div className="min-w-0">
                <p className="text-xs font-semibold text-white truncate">{songInfo.title}</p>
                <p className="text-[10px] text-gray-500 mt-0.5">YouTube Audio</p>
              </div>
            </div>
          )}

          {/* URL Input */}
          {status === 'idle' || status === 'error' ? (
            <div className="space-y-2">
              <div className="relative">
                <Youtube className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-red-500/60" />
                <input
                  type="url"
                  placeholder="https://youtube.com/watch?v=..."
                  value={url}
                  onChange={(e) => { setUrl(e.target.value); setError(''); }}
                  className="w-full pl-9 pr-4 py-2.5 bg-[#0a0a0a] border border-white/10 rounded-lg text-xs text-white placeholder-gray-600 focus:outline-none focus:border-red-500/50 transition-all"
                />
              </div>
              {error && (
                <p className="text-[10px] text-red-400">{error}</p>
              )}
            </div>
          ) : null}

          {/* Progress */}
          {(status === 'fetching' || status === 'downloading') && (
            <div className="flex items-center gap-3 p-3 bg-[#0a0a0a] rounded-lg border border-[#c8f500]/10">
              <Loader2 className="w-4 h-4 text-[#c8f500] animate-spin flex-shrink-0" />
              <p className="text-xs text-gray-300">{progress}</p>
            </div>
          )}

          {/* Done */}
          {status === 'done' && (
            <div className="flex items-center gap-3 p-3 bg-green-500/5 rounded-lg border border-green-500/20">
              <CheckCircle className="w-4 h-4 text-green-400 flex-shrink-0" />
              <p className="text-xs text-green-300">Berhasil disimpan ke library!</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 pb-5 flex gap-2">
          {status === 'idle' || status === 'error' ? (
            <>
              <button
                onClick={handleClose}
                className="flex-1 py-2.5 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg text-xs font-semibold transition-colors cursor-pointer"
              >
                Batal
              </button>
              <button
                onClick={handleDownload}
                disabled={!url.trim()}
                className="flex-1 py-2.5 bg-red-500 hover:bg-red-600 disabled:opacity-40 disabled:cursor-not-allowed text-white rounded-lg text-xs font-bold flex items-center justify-center gap-1.5 transition-colors cursor-pointer"
              >
                <Download className="w-3.5 h-3.5" />
                Download
              </button>
            </>
          ) : status === 'done' ? (
            <>
              <button
                onClick={handleReset}
                className="flex-1 py-2.5 bg-[#111] border border-gray-700 text-gray-300 hover:text-white rounded-lg text-xs font-semibold transition-colors cursor-pointer"
              >
                Download Lagi
              </button>
              <button
                onClick={handleClose}
                className="flex-1 py-2.5 bg-[#c8f500] text-black rounded-lg text-xs font-bold transition-colors cursor-pointer"
              >
                Selesai
              </button>
            </>
          ) : (
            <div className="flex-1 py-2.5 text-center text-xs text-gray-500">
              Sedang mengunduh, harap tunggu...
            </div>
          )}
        </div>

      </div>
    </div>
  );
}
