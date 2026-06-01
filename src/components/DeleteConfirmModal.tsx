import React from 'react';
import { Trash2, X, EyeOff, AlertTriangle } from 'lucide-react';
import { LocalSong } from '../lib/db';
import { isCapacitorActive } from '../lib/mobileScanner';

interface DeleteConfirmModalProps {
  isOpen: boolean;
  song: LocalSong | null;
  onHide: () => void;       // Sembunyikan dari library (file tetap)
  onDeleteFile: () => void; // Hapus file dari HP
  onCancel: () => void;
}

export default function DeleteConfirmModal({
  isOpen,
  song,
  onHide,
  onDeleteFile,
  onCancel
}: DeleteConfirmModalProps) {
  if (!isOpen || !song) return null;

  const canDeleteFile = isCapacitorActive();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-sm p-6 rounded-xl bg-[#111] border border-gray-700/50 shadow-[0_0_30px_rgba(0,0,0,0.5)] animate-scale-up">
        <button onClick={onCancel} className="absolute top-4 right-4 text-gray-400 hover:text-white transition-colors">
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-full bg-gray-700/50 flex items-center justify-center flex-shrink-0">
            <Trash2 className="w-5 h-5 text-gray-300" />
          </div>
          <h3 className="text-xl font-heading text-white tracking-wider leading-none">HAPUS LAGU</h3>
        </div>

        <p className="text-xs text-gray-500 font-body mb-1">Lagu yang dipilih:</p>
        <p className="text-sm text-white font-semibold font-body truncate mb-5">
          "{song.title}"
        </p>

        <p className="text-xs text-gray-400 font-body mb-4">Pilih cara menghapus:</p>

        <div className="space-y-3">
          {/* Option 1: Sembunyikan */}
          <button
            type="button"
            onClick={onHide}
            className="w-full p-4 rounded-xl bg-[#1a1a1a] border border-[#c8f500]/20 hover:border-[#c8f500]/50 hover:bg-[#c8f500]/5 text-left transition-all cursor-pointer group"
          >
            <div className="flex items-center gap-3 mb-1">
              <EyeOff className="w-4 h-4 text-[#c8f500] flex-shrink-0" />
              <span className="text-sm font-semibold text-white group-hover:text-[#c8f500] transition-colors">
                Sembunyikan dari Library
              </span>
            </div>
            <p className="text-xs text-gray-500 ml-7 leading-relaxed">
              File tetap ada di HP, tapi tidak akan muncul lagi di KyokoBeat — bahkan setelah scan ulang.
            </p>
          </button>

          {/* Option 2: Hapus File */}
          {canDeleteFile ? (
            <button
              type="button"
              onClick={onDeleteFile}
              className="w-full p-4 rounded-xl bg-[#1a1a1a] border border-red-500/20 hover:border-red-500/50 hover:bg-red-500/5 text-left transition-all cursor-pointer group"
            >
              <div className="flex items-center gap-3 mb-1">
                <Trash2 className="w-4 h-4 text-red-400 flex-shrink-0" />
                <span className="text-sm font-semibold text-white group-hover:text-red-400 transition-colors">
                  Hapus File dari HP
                </span>
              </div>
              <p className="text-xs text-gray-500 ml-7 leading-relaxed">
                File dihapus permanen dari penyimpanan HP. Tidak bisa dikembalikan.
              </p>
            </button>
          ) : (
            <div className="w-full p-4 rounded-xl bg-[#1a1a1a] border border-gray-800 opacity-50">
              <div className="flex items-center gap-3 mb-1">
                <AlertTriangle className="w-4 h-4 text-yellow-500 flex-shrink-0" />
                <span className="text-sm font-semibold text-gray-400">
                  Hapus File (hanya di HP)
                </span>
              </div>
              <p className="text-xs text-gray-600 ml-7">
                Fitur ini hanya tersedia di aplikasi Android KyokoBeat.
              </p>
            </div>
          )}
        </div>

        <button
          type="button"
          onClick={onCancel}
          className="w-full mt-4 py-2.5 bg-transparent border border-gray-800 text-gray-400 hover:text-white rounded-lg hover:bg-gray-900 transition-colors text-sm cursor-pointer"
        >
          Batal
        </button>
      </div>
    </div>
  );
}
