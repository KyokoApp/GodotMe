import React, { useState, useEffect } from 'react';
import { X, Plus, FolderHeart, Music, Check } from 'lucide-react';
import { LocalSong, LocalPlaylist, getPlaylists, savePlaylist } from '../lib/db';
import { useToast } from './Toast';

interface PlaylistModalProps {
  isOpen: boolean;
  onClose: () => void;
  song: LocalSong | null;
  onPlaylistUpdated: () => void;
}

export default function PlaylistModal({ isOpen, onClose, song, onPlaylistUpdated }: PlaylistModalProps) {
  const [playlists, setPlaylists] = useState<LocalPlaylist[]>([]);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [showCreateForm, setShowCreateForm] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    if (isOpen) {
      loadPlaylists();
    }
  }, [isOpen]);

  const loadPlaylists = async () => {
    const list = await getPlaylists();
    setPlaylists(list);
  };

  if (!isOpen || !song) return null;

  const handleCreatePlaylist = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newPlaylistName.trim()) return;

    const newPlaylist: LocalPlaylist = {
      id: Math.random().toString(36).substring(2, 9),
      name: newPlaylistName.trim(),
      description: 'Local playlist',
      songIds: [song.id],
      createdAt: Date.now()
    };

    await savePlaylist(newPlaylist);
    toast(`Playlist "${newPlaylist.name}" dibuat & lagu ditambahkan`, 'success');
    setNewPlaylistName('');
    setShowCreateForm(false);
    loadPlaylists();
    onPlaylistUpdated();
    onClose();
  };

  const handleAddToPlaylist = async (playlist: LocalPlaylist) => {
    if (playlist.songIds.includes(song.id)) {
      toast(`Lagu sudah ada di playlist "${playlist.name}"`, 'info');
      return;
    }

    const updatedPlaylist = {
      ...playlist,
      songIds: [...playlist.songIds, song.id]
    };

    await savePlaylist(updatedPlaylist);
    toast(`Lagu ditambahkan ke playlist "${playlist.name}"`, 'success');
    loadPlaylists();
    onPlaylistUpdated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <div className="relative w-full max-w-sm p-6 rounded-xl bg-[#111] border border-[#c8f500]/30 shadow-[0_0_30px_rgba(200,245,0,0.15)] animate-scale-up">
        {/* Close */}
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-gray-400 hover:text-[#c8f500] transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Title */}
        <h3 className="text-2xl font-heading text-[#c8f500] mb-1">TAMBAH KE PLAYLIST</h3>
        <p className="text-xs text-gray-400 font-body mb-4 truncate">
          Lagu: <span className="text-white font-medium">{song.title}</span>
        </p>

        {/* Playlists List */}
        <div className="space-y-2 max-h-60 overflow-y-auto pr-1 mb-4">
          {playlists.length === 0 ? (
            <div className="text-center py-6 text-gray-500 font-body text-sm">
              <Music className="w-8 h-8 mx-auto mb-2 opacity-30 text-white" />
              Belum ada playlist
            </div>
          ) : (
            playlists.map((pl) => {
              const alreadyIn = pl.songIds.includes(song.id);
              return (
                <button
                  key={pl.id}
                  onClick={() => handleAddToPlaylist(pl)}
                  disabled={alreadyIn}
                  className={`w-full flex items-center justify-between p-3 rounded-lg border text-left font-body transition-all duration-200 cursor-pointer ${
                    alreadyIn
                      ? 'bg-[#1a1a1a] border-gray-800 text-gray-500'
                      : 'bg-[#0a0a0a] border-[#c8f500]/10 text-white hover:border-[#c8f500]/40 hover:shadow-[0_0_10px_rgba(200,245,0,0.05)]'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <FolderHeart className={`w-5 h-5 ${alreadyIn ? 'text-gray-600' : 'text-[#c8f500]'}`} />
                    <div>
                      <div className="text-sm font-semibold truncate max-w-[180px]">{pl.name}</div>
                      <div className="text-xs text-gray-500">{pl.songIds.length} Lagu</div>
                    </div>
                  </div>
                  {alreadyIn && <Check className="w-4 h-4 text-[#c8f500]" />}
                </button>
              );
            })
          )}
        </div>

        {/* Create Form Toggle */}
        {!showCreateForm ? (
          <button
            onClick={() => setShowCreateForm(true)}
            className="w-full py-2.5 bg-transparent border border-dashed border-[#c8f500]/30 text-[#c8f500] hover:bg-[#c8f500]/5 text-sm font-semibold rounded-lg transition-colors flex items-center justify-center gap-2 font-body cursor-pointer"
          >
            <Plus className="w-4 h-4" /> Buat Playlist Baru
          </button>
        ) : (
          <form onSubmit={handleCreatePlaylist} className="space-y-2 mt-2 font-body">
            <input
              type="text"
              placeholder="Nama Playlist Baru..."
              value={newPlaylistName}
              onChange={(e) => setNewPlaylistName(e.target.value)}
              className="w-full px-3 py-2 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
              autoFocus
            />
            <div className="flex gap-2">
              <button
                type="submit"
                className="flex-1 py-2 bg-[#c8f500] text-black text-xs font-bold rounded-lg hover:shadow-[0_0_10px_rgba(200,245,0,0.3)] transition-all cursor-pointer"
              >
                Buat & Tambah
              </button>
              <button
                type="button"
                onClick={() => setShowCreateForm(false)}
                className="flex-1 py-2 bg-transparent border border-gray-800 text-gray-400 text-xs font-semibold rounded-lg hover:bg-gray-900 transition-colors cursor-pointer"
              >
                Batal
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
