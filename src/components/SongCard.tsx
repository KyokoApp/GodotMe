import React, { useState, useRef, useEffect } from 'react';
import { Play, Pause, Heart, Plus, Cloud, Laptop, MoreVertical, Edit2, Trash2, Download, Loader2 } from 'lucide-react';
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
  isDownloading?: boolean;
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
  isDownloading = false,
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
        {/* Album Art / Animated Music Visual */}
        <div className="relative w-12 h-12 rounded-lg overflow-hidden bg-[#1a1a1a] flex-shrink-0 border border-white/5">
          {song.cover ? (
            <img
              src={song.cover}
              alt={song.title}
              className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
              onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
            />
          ) : (
            /* Default music icon placeholder */
            <div className={`w-full h-full flex items-center justify-center transition-all duration-300 ${
              isCurrentlyPlaying ? 'bg-[#0d1a00]' : 'bg-[#151515]'
            }`}>
              {isCurrentlyPlaying ? (
                /* Animated music bars when playing */
                <div className="flex items-end gap-[3px] h-6">
                  {[0, 1, 2, 3].map((i) => (
                    <div
                      key={i}
                      className="w-[3px] rounded-full bg-[#c8f500]"
                      style={{
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
                /* Static music note icon */
                <svg className={`w-6 h-6 transition-colors duration-300 ${isCurrent ? 'text-[#c8f500]/60' : 'text-gray-600'}`} viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>
                </svg>
              )}
            </div>
          )}

          {/* Hover Play/Pause overlay */}
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
            <div className="absolute right-0 mt-1 w-44 rounded-lg bg-[#151515] border border-gray-800 shadow-[0_4px_12px_rgba(0,0,0,0.5)] py-1.5 z-30 font-body animate-scale-up">
              <button
                onClick={() => { onAddToPlaylist(); setShowDropdown(false); }}
                className="w-full px-4 py-2 text-left text-xs text-gray-300 hover:bg-[#c8f500]/10 hover:text-[#c8f500] flex items-center gap-2 cursor-pointer transition-colors"
              >
                <Plus className="w-3.5 h-3.5" />
                Tambah ke Playlist
              </button>

              {song.isCloud ? (
                /* Cloud song: bisa download ke offline */
                <button
                  onClick={() => { onDownload?.(song); setShowDropdown(false); }}
                  disabled={isDownloading}
                  className="w-full px-4 py-2 text-left text-xs text-blue-400 hover:bg-blue-500/10 hover:text-blue-300 flex items-center gap-2 cursor-pointer transition-colors disabled:opacity-50"
                >
                  {isDownloading ? (
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  ) : (
                    <Download className="w-3.5 h-3.5" />
                  )}
                  {isDownloading ? 'Mengunduh...' : 'Download ke Offline'}
                </button>
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
