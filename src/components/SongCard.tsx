import React, { useState, useRef, useEffect } from 'react';
import { Play, Pause, Heart, Plus, Cloud, Laptop, MoreVertical, Edit2, Trash2, Download, Loader2, CheckCircle } from 'lucide-react';
import { LocalSong } from '../lib/db';

interface SongCardProps {
  song: LocalSong;
  isCurrent: boolean;
  isPlaying: boolean;
  isFav: boolean;
  onPlay: () => void;
  onToggleFav: () => void;
  onAddToPlaylist: () => void;
  onRename: (song: LocalSong) => void;
  onDelete: (song: LocalSong) => void;
  onDownload?: (song: LocalSong) => void;
  onDeleteCloud?: (song: LocalSong) => void; // admin only
  isDownloading?: boolean;
  isDownloaded?: boolean; // already downloaded from cloud
}

export default function SongCard({
  song,
  isCurrent,
  isPlaying,
  isFav,
  onPlay,
  onToggleFav,
  onAddToPlaylist,
  onRename,
  onDelete,
  onDownload,
  onDeleteCloud,
  isDownloading = false,
  isDownloaded = false,
}: SongCardProps) {
  const [showDropdown, setShowDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowDropdown(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const formatTime = (secs: number) => {
    if (isNaN(secs) || secs === 0) return '--:--';
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  const isCurrentlyPlaying = isCurrent && isPlaying;

  return (
    <div
      className={`group relative flex items-center justify-between p-3 rounded-xl bg-[#111] border transition-all duration-300 ${
        isCurrent
          ? 'border-[#c8f500] shadow-[0_0_15px_rgba(200,245,0,0.15)] bg-[#111]'
          : 'border-[#c8f500]/5 hover:border-[#c8f500]/20 hover:shadow-[0_0_15px_rgba(200,245,0,0.05)]'
      } transform hover:-translate-y-1`}
    >
      <div className="flex items-center gap-4 min-w-0 flex-1">
        {/* Album Art */}
        <div className="relative w-12 h-12 rounded-lg overflow-hidden bg-[#1a1a1a] flex-shrink-0 border border-white/5">
          {song.cover ? (
            <img
              src={song.cover}
              alt={song.title}
              className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
              onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
            />
          ) : (() => {
            // Generate warna unik berdasarkan title — tiap lagu punya "warna" nya sendiri
            const colors = [
              ['#1a0a2e', '#7c3aed'], // purple
              ['#0a1a2e', '#2563eb'], // blue
              ['#0a2e1a', '#16a34a'], // green
              ['#2e1a0a', '#ea580c'], // orange
              ['#2e0a1a', '#db2777'], // pink
              ['#1a2e0a', '#65a30d'], // lime
              ['#0a2e2e', '#0891b2'], // cyan
              ['#2e2e0a', '#ca8a04'], // yellow
            ];
            const idx = (song.title?.charCodeAt(0) || 0) % colors.length;
            const [bg, accent] = colors[idx];
            // Inisial dari title
            const initials = song.title
              ? song.title.replace(/^\[.*?\]\s*/, '').slice(0, 2).toUpperCase()
              : '♪';
            return (
              <div
                className="w-full h-full flex flex-col items-center justify-center gap-0.5 transition-all duration-300"
                style={{ background: `linear-gradient(135deg, ${bg} 0%, ${bg}cc 100%)` }}
              >
                {isCurrentlyPlaying ? (
                  <div className="flex items-end gap-[3px] h-5">
                    {[0, 1, 2, 3].map((i) => (
                      <div
                        key={i}
                        className="w-[3px] rounded-full"
                        style={{
                          background: accent,
                          animation: `musicBar 0.8s ease-in-out infinite`,
                          animationDelay: `${i * 0.15}s`,
                          height: '100%',
                        }}
                      />
                    ))}
                    <style>{`
                      @keyframes musicBar {
                        0%, 100% { transform: scaleY(0.2); }
                        50% { transform: scaleY(1); }
                      }
                    `}</style>
                  </div>
                ) : (
                  <>
                    <span
                      className="text-[13px] font-black leading-none tracking-tight"
                      style={{ color: accent }}
                    >
                      {initials}
                    </span>
                    <div
                      className="w-4 h-[2px] rounded-full opacity-40"
                      style={{ background: accent }}
                    />
                  </>
                )}
              </div>
            );
          })()}

          <button
            onClick={onPlay}
            className={`absolute inset-0 flex items-center justify-center bg-black/60 transition-opacity duration-200 cursor-pointer ${
              isCurrent ? 'opacity-100 bg-black/40' : 'opacity-0 group-hover:opacity-100'
            }`}
          >
            {isCurrent && isPlaying ? (
              <Pause className="w-5 h-5 text-[#c8f500] fill-[#c8f500]" />
            ) : (
              <Play className="w-5 h-5 text-[#c8f500] fill-[#c8f500]" />
            )}
          </button>
        </div>

        {/* Metadata */}
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <h4
              onClick={onPlay}
              className={`text-sm font-semibold font-body truncate cursor-pointer hover:text-[#c8f500] transition-colors ${
                isCurrent ? 'text-[#c8f500]' : 'text-white'
              }`}
            >
              {song.title}
            </h4>
            {song.isCloud ? (
              <span title="Cloud Track"><Cloud className="w-3.5 h-3.5 text-blue-400 flex-shrink-0" /></span>
            ) : (
              <span title="Local Track"><Laptop className="w-3.5 h-3.5 text-gray-400 flex-shrink-0" /></span>
            )}
          </div>
          <p className="text-xs text-gray-400 font-body truncate mt-0.5">{song.artist}</p>
          <p className="text-[10px] text-gray-500 font-body truncate mt-0.5">{song.album}</p>
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2 ml-4">
        <span className="text-xs text-gray-500 font-body mr-1 hidden sm:inline">
          {formatTime(song.duration)}
        </span>

        <button
          onClick={onToggleFav}
          className="p-2 text-gray-400 hover:text-red-500 transition-colors cursor-pointer"
        >
          <Heart className={`w-4 h-4 ${isFav ? 'text-red-500 fill-red-500' : ''}`} />
        </button>

        <div className="relative" ref={dropdownRef}>
          <button
            onClick={() => setShowDropdown(!showDropdown)}
            className="p-2 text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer"
          >
            <MoreVertical className="w-4 h-4" />
          </button>

          {showDropdown && (
            <div className="absolute right-0 mt-1 w-48 rounded-lg bg-[#151515] border border-gray-800 shadow-[0_4px_12px_rgba(0,0,0,0.5)] py-1.5 z-30 font-body animate-scale-up">
              <button
                onClick={() => { onAddToPlaylist(); setShowDropdown(false); }}
                className="w-full px-4 py-2 text-left text-xs text-gray-300 hover:bg-[#c8f500]/10 hover:text-[#c8f500] flex items-center gap-2 cursor-pointer transition-colors"
              >
                <Plus className="w-3.5 h-3.5" />
                Tambah ke Playlist
              </button>

              {song.isCloud ? (
                <>
                  {/* Download button */}
                  <button
                    onClick={() => { onDownload?.(song); setShowDropdown(false); }}
                    disabled={isDownloading || isDownloaded}
                    className="w-full px-4 py-2 text-left text-xs text-blue-400 hover:bg-blue-500/10 hover:text-blue-300 flex items-center gap-2 cursor-pointer transition-colors disabled:opacity-50"
                  >
                    {isDownloading ? (
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    ) : isDownloaded ? (
                      <CheckCircle className="w-3.5 h-3.5 text-green-400" />
                    ) : (
                      <Download className="w-3.5 h-3.5" />
                    )}
                    {isDownloading ? 'Mengunduh...' : isDownloaded ? 'Sudah Diunduh' : 'Download ke Offline'}
                  </button>

                  {/* Admin-only: delete from cloud */}
                  {onDeleteCloud && (
                    <button
                      onClick={() => { onDeleteCloud(song); setShowDropdown(false); }}
                      className="w-full px-4 py-2 text-left text-xs text-red-400 hover:bg-red-500/10 hover:text-red-500 flex items-center gap-2 cursor-pointer transition-colors"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                      Hapus dari Cloud
                    </button>
                  )}
                </>
              ) : (
                <>
                  <button
                    onClick={() => { onRename(song); setShowDropdown(false); }}
                    className="w-full px-4 py-2 text-left text-xs text-gray-300 hover:bg-[#c8f500]/10 hover:text-[#c8f500] flex items-center gap-2 cursor-pointer transition-colors"
                  >
                    <Edit2 className="w-3.5 h-3.5" />
                    Ubah Nama / Tag
                  </button>

                  <button
                    onClick={() => { onDelete(song); setShowDropdown(false); }}
                    className="w-full px-4 py-2 text-left text-xs text-red-400 hover:bg-red-500/10 hover:text-red-500 flex items-center gap-2 cursor-pointer transition-colors"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                    Hapus Lagu
                  </button>
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
