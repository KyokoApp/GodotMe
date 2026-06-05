import React, { useState } from 'react';
import { X, Link, Check, Music, Lock } from 'lucide-react';
import { LocalPlaylist, LocalSong } from '../lib/db';

interface SharePlaylistModalProps {
  playlist: LocalPlaylist;
  songs: LocalSong[];
  onClose: () => void;
}

export default function SharePlaylistModal({ playlist, songs, onClose }: SharePlaylistModalProps) {
  const [copied, setCopied] = useState(false);
  const [isPublic, setIsPublic] = useState(false);
  const [shareId] = useState(() => {
    // Generate or retrieve existing share ID
    const key = `share_id_${playlist.id}`;
    const existing = localStorage.getItem(key);
    if (existing) return existing;
    const newId = Math.random().toString(36).substring(2, 10);
    localStorage.setItem(key, newId);
    return newId;
  });

  const shareUrl = `${window.location.origin}/playlist/${shareId}`;
  const playlistSongs = songs.filter(s => playlist.songIds.includes(s.id));

  const handleCopy = () => {
    navigator.clipboard.writeText(shareUrl).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  // Save playlist data to localStorage so share page can read it
  const handleTogglePublic = () => {
    const next = !isPublic;
    setIsPublic(next);
    if (next) {
      const shareData = {
        id: shareId,
        name: playlist.name,
        createdAt: playlist.createdAt,
        songs: playlistSongs.map(s => ({
          title: s.title,
          artist: s.artist,
          album: s.album,
          duration: s.duration,
        })),
      };
      localStorage.setItem(`shared_playlist_${shareId}`, JSON.stringify(shareData));
    } else {
      localStorage.removeItem(`shared_playlist_${shareId}`);
    }
  };

  const formatDuration = (sec: number) => {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  const totalDuration = playlistSongs.reduce((a, s) => a + (s.duration || 0), 0);
  const totalMin = Math.floor(totalDuration / 60);

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      onClick={onClose}
    >
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" />
      <div
        className="relative w-full max-w-md bg-[#0d0d0d] border border-white/10 rounded-t-2xl sm:rounded-2xl p-5 z-10 animate-slide-up"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between mb-5">
          <div>
            <h2 className="text-base font-bold text-white tracking-wide">Share Playlist</h2>
            <p className="text-xs text-gray-500 mt-0.5 truncate max-w-[240px]">{playlist.name}</p>
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-gray-400 hover:text-white transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Playlist preview */}
        <div className="bg-[#111] border border-white/5 rounded-xl p-3 mb-4">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 rounded-lg bg-[#c8f500]/10 border border-[#c8f500]/20 flex items-center justify-center flex-shrink-0">
              <Music className="w-5 h-5 text-[#c8f500]" />
            </div>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-white truncate">{playlist.name}</p>
              <p className="text-[11px] text-gray-500">
                {playlistSongs.length} lagu • {totalMin} menit
              </p>
            </div>
          </div>

          {/* Song list preview (max 4) */}
          <div className="space-y-1.5">
            {playlistSongs.slice(0, 4).map((s, i) => (
              <div key={s.id} className="flex items-center gap-2">
                <span className="text-[10px] text-gray-600 w-4 text-right flex-shrink-0">{i + 1}</span>
                <div className="flex-1 min-w-0 flex items-center justify-between">
                  <span className="text-[11px] text-gray-300 truncate">{s.title}</span>
                  <span className="text-[10px] text-gray-600 ml-2 flex-shrink-0">{formatDuration(s.duration)}</span>
                </div>
              </div>
            ))}
            {playlistSongs.length > 4 && (
              <p className="text-[10px] text-gray-600 pl-6">+{playlistSongs.length - 4} lagu lagi...</p>
            )}
          </div>
        </div>

        {/* Toggle public */}
        <div
          onClick={handleTogglePublic}
          className={`flex items-center justify-between p-3 rounded-xl border cursor-pointer transition-all mb-4 ${
            isPublic
              ? 'bg-[#c8f500]/8 border-[#c8f500]/30'
              : 'bg-white/3 border-white/8 hover:border-white/15'
          }`}
        >
          <div className="flex items-center gap-2.5">
            {isPublic
              ? <Link className="w-4 h-4 text-[#c8f500]" />
              : <Lock className="w-4 h-4 text-gray-500" />
            }
            <div>
              <p className={`text-xs font-semibold ${isPublic ? 'text-[#c8f500]' : 'text-gray-400'}`}>
                {isPublic ? 'Link Aktif' : 'Buat Link Publik'}
              </p>
              <p className="text-[10px] text-gray-600">
                {isPublic ? 'Siapa saja bisa lihat playlist ini' : 'Tap untuk generate link share'}
              </p>
            </div>
          </div>
          <div className={`w-9 h-5 rounded-full transition-all relative ${isPublic ? 'bg-[#c8f500]' : 'bg-white/10'}`}>
            <div className={`absolute top-0.5 w-4 h-4 rounded-full bg-black transition-all ${isPublic ? 'left-[18px]' : 'left-0.5'}`} />
          </div>
        </div>

        {/* Share URL (only visible when public) */}
        {isPublic && (
          <div className="flex gap-2 animate-fade-in">
            <div className="flex-1 bg-[#111] border border-white/10 rounded-xl px-3 py-2.5 min-w-0">
              <p className="text-[11px] text-gray-400 truncate">{shareUrl}</p>
            </div>
            <button
              onClick={handleCopy}
              className={`flex-shrink-0 px-4 py-2.5 rounded-xl text-xs font-bold transition-all cursor-pointer ${
                copied
                  ? 'bg-green-500/20 border border-green-500/40 text-green-400'
                  : 'bg-[#c8f500] text-black hover:bg-[#d4ff00]'
              }`}
            >
              {copied ? <Check className="w-4 h-4" /> : 'Copy'}
            </button>
          </div>
        )}

        {isPublic && (
          <p className="text-[10px] text-gray-600 mt-2 text-center">
            Link hanya berlaku di perangkat ini (local share)
          </p>
        )}
      </div>
    </div>
  );
}
