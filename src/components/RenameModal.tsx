import React, { useState, useEffect } from 'react';
import { X, Save, Edit2 } from 'lucide-react';
import { LocalSong, saveSong } from '../lib/db';
import { useToast } from './Toast';

interface RenameModalProps {
  isOpen: boolean;
  onClose: () => void;
  song: LocalSong | null;
  onRenameSuccess: () => void;
}

export default function RenameModal({ isOpen, onClose, song, onRenameSuccess }: RenameModalProps) {
  const [title, setTitle] = useState('');
  const [artist, setArtist] = useState('');
  const [album, setAlbum] = useState('');
  const [loading, setLoading] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    if (song) {
      setTitle(song.title);
      setArtist(song.artist);
      setAlbum(song.album);
    }
  }, [song, isOpen]);

  if (!isOpen || !song) return null;

  const handleSave = async () => {
    if (!title.trim()) {
      toast('Judul lagu tidak boleh kosong', 'error');
      return;
    }
    setLoading(true);
    try {
      const updatedSong: LocalSong = {
        ...song,
        title: title.trim(),
        artist: artist.trim() || 'Unknown Artist',
        album: album.trim() || 'Unknown Album'
      };
      await saveSong(updatedSong);
      toast('Metadata lagu berhasil diperbarui!', 'success');
      onRenameSuccess();
      onClose();
    } catch (err: any) {
      console.error(err);
      toast('Gagal memperbarui nama lagu: ' + err.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-md p-6 rounded-xl bg-[#111] border border-[#c8f500]/30 shadow-[0_0_30px_rgba(200,245,0,0.15)] animate-scale-up">
        <button onClick={onClose} className="absolute top-4 right-4 text-gray-400 hover:text-[#c8f500] transition-colors">
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-2 mb-4">
          <Edit2 className="w-5 h-5 text-[#c8f500]" />
          <h3 className="text-2xl font-heading text-[#c8f500] tracking-wider leading-none">UBAH METADATA LAGU</h3>
        </div>
        <p className="text-xs text-gray-400 font-body mb-6">
          Ubah judul, nama artis, dan album lagu lokal ini. Perubahan akan disimpan secara permanen di IndexedDB.
        </p>

        <div className="space-y-4 font-body">
          <div>
            <label className="block text-xs text-gray-400 mb-1">Judul Lagu</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full px-4 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-400 mb-1">Nama Artis</label>
            <input
              type="text"
              value={artist}
              onChange={(e) => setArtist(e.target.value)}
              className="w-full px-4 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-400 mb-1">Nama Album</label>
            <input
              type="text"
              value={album}
              onChange={(e) => setAlbum(e.target.value)}
              className="w-full px-4 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
            />
          </div>

          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={handleSave}
              disabled={loading}
              className="flex-1 py-3 bg-[#c8f500] text-black font-semibold rounded-lg hover:shadow-[0_0_15px_rgba(200,245,0,0.4)] transition-all duration-300 flex items-center justify-center gap-2 cursor-pointer text-sm"
            >
              {loading ? (
                <span className="w-4 h-4 border-2 border-black border-t-transparent rounded-full animate-spin"></span>
              ) : (
                <><Save className="w-4 h-4" /> Simpan Perubahan</>
              )}
            </button>
            <button
              type="button"
              onClick={onClose}
              className="flex-1 py-3 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg hover:bg-gray-900 transition-colors text-sm cursor-pointer"
            >
              Batal
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
