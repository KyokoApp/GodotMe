import React from 'react';
import { Trash2, X } from 'lucide-react';
import { LocalSong } from '../lib/db';

interface DeleteConfirmModalProps {
  isOpen: boolean;
  song: LocalSong | null;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function DeleteConfirmModal({ isOpen, song, onConfirm, onCancel }: DeleteConfirmModalProps) {
  if (!isOpen || !song) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-sm p-6 rounded-xl bg-[#111] border border-red-500/30 shadow-[0_0_30px_rgba(239,68,68,0.15)] animate-scale-up">
        <button onClick={onCancel} className="absolute top-4 right-4 text-gray-400 hover:text-white transition-colors">
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-3 mb-3">
          <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center flex-shrink-0">
            <Trash2 className="w-5 h-5 text-red-400" />
          </div>
          <h3 className="text-xl font-heading text-white tracking-wider leading-none">HAPUS LAGU</h3>
        </div>

        <p className="text-sm text-gray-400 font-body mb-1">
          Yakin ingin menghapus lagu ini dari library?
        </p>
        <p className="text-sm text-white font-semibold font-body truncate mb-6">
          "{song.title}"
        </p>

        <div className="flex gap-3">
          <button
            type="button"
            onClick={onConfirm}
            className="flex-1 py-3 bg-red-500 text-white font-semibold rounded-lg hover:bg-red-600 transition-colors flex items-center justify-center gap-2 cursor-pointer text-sm"
          >
            <Trash2 className="w-4 h-4" /> Hapus
          </button>
          <button
            type="button"
            onClick={onCancel}
            className="flex-1 py-3 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg hover:bg-gray-900 transition-colors text-sm cursor-pointer"
          >
            Batal
          </button>
        </div>
      </div>
    </div>
  );
}
