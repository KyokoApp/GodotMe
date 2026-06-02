import React, { useState } from 'react';
import { Download, X, Sparkles, AlertCircle } from 'lucide-react';
import { UpdateInfo, downloadAndInstall } from '../lib/updater';

interface Props {
  info: UpdateInfo;
  onDismiss: () => void;
}

export default function UpdateDialog({ info, onDismiss }: Props) {
  const [state, setState] = useState<'idle' | 'downloading' | 'done' | 'error'>('idle');
  const [progress, setProgress] = useState(0);
  const [errorMsg, setErrorMsg] = useState('');

  const handleUpdate = async () => {
    setState('downloading');
    setProgress(0);
    try {
      await downloadAndInstall(info.apkUrl, (pct) => setProgress(pct));
      setState('done');
    } catch (e: any) {
      setErrorMsg(e.message || 'Gagal mengunduh update');
      setState('error');
    }
  };

  return (
    <div className="fixed inset-0 z-[100] flex items-end justify-center p-4 bg-black/70 backdrop-blur-sm">
      <div className="w-full max-w-md rounded-2xl bg-[#111] border border-[#c8f500]/30 shadow-[0_0_40px_rgba(200,245,0,0.15)] overflow-hidden animate-slide-up font-body">
        
        {/* Header */}
        <div className="relative p-5 bg-gradient-to-r from-[#c8f500]/10 to-transparent border-b border-[#c8f500]/10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-[#c8f500]/10 border border-[#c8f500]/30 flex items-center justify-center flex-shrink-0">
              <Sparkles className="w-5 h-5 text-[#c8f500]" />
            </div>
            <div>
              <h3 className="text-base font-heading text-[#c8f500] tracking-wider">UPDATE TERSEDIA</h3>
              <p className="text-xs text-gray-400 mt-0.5">KyokoBeat v{info.version}</p>
            </div>
          </div>
          {state === 'idle' && (
            <button
              onClick={onDismiss}
              className="absolute top-4 right-4 text-gray-500 hover:text-white transition-colors cursor-pointer"
            >
              <X className="w-5 h-5" />
            </button>
          )}
        </div>

        {/* Changelog */}
        <div className="p-5">
          <p className="text-xs text-gray-400 mb-1 uppercase tracking-wider">Yang baru:</p>
          <p className="text-sm text-gray-300 leading-relaxed whitespace-pre-line">{info.changelog}</p>
        </div>

        {/* Progress */}
        {state === 'downloading' && (
          <div className="px-5 pb-2">
            <div className="flex justify-between text-xs text-gray-400 mb-1.5">
              <span>Mengunduh update...</span>
              <span>{progress}%</span>
            </div>
            <div className="w-full h-1.5 bg-[#1a1a1a] rounded-full overflow-hidden">
              <div
                className="h-full bg-[#c8f500] rounded-full transition-all duration-300"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>
        )}

        {state === 'done' && (
          <div className="px-5 pb-2">
            <div className="p-3 rounded-lg bg-green-500/10 border border-green-500/20 text-xs text-green-400">
              ✅ Download selesai! Ikuti instruksi install yang muncul.
            </div>
          </div>
        )}

        {state === 'error' && (
          <div className="px-5 pb-2">
            <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/20 flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-red-400 flex-shrink-0 mt-0.5" />
              <p className="text-xs text-red-400">{errorMsg}</p>
            </div>
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-3 p-5 pt-3">
          {state === 'idle' && (
            <>
              <button
                onClick={onDismiss}
                className="flex-1 py-2.5 rounded-lg border border-gray-700 text-gray-400 hover:text-white hover:border-gray-500 text-sm transition-colors cursor-pointer"
              >
                Nanti Saja
              </button>
              <button
                onClick={handleUpdate}
                className="flex-1 py-2.5 rounded-lg bg-[#c8f500] text-black font-semibold text-sm hover:shadow-[0_0_15px_rgba(200,245,0,0.4)] transition-all flex items-center justify-center gap-2 cursor-pointer"
              >
                <Download className="w-4 h-4" />
                Update Sekarang
              </button>
            </>
          )}

          {state === 'downloading' && (
            <div className="flex-1 py-2.5 rounded-lg bg-[#c8f500]/20 text-[#c8f500] text-sm text-center">
              Mengunduh... {progress}%
            </div>
          )}

          {(state === 'done' || state === 'error') && (
            <button
              onClick={onDismiss}
              className="flex-1 py-2.5 rounded-lg border border-gray-700 text-gray-400 hover:text-white text-sm transition-colors cursor-pointer"
            >
              Tutup
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
