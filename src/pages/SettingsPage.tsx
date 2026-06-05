import React, { useState } from 'react';
import { ArrowLeft, RefreshCw, Download, CheckCircle, AlertCircle } from 'lucide-react';
import { checkForUpdate, CURRENT_VERSION, UpdateInfo } from '../lib/updater';
import UpdateDialog from '../components/UpdateDialog';

interface SettingsPageProps {
  onBack: () => void;
}

export default function SettingsPage({ onBack }: SettingsPageProps) {
  const [checkState, setCheckState] = useState<'idle' | 'checking' | 'found' | 'latest' | 'error'>('idle');
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [showDialog, setShowDialog] = useState(false);

  const handleCheckUpdate = async () => {
    setCheckState('checking');
    try {
      const info = await checkForUpdate();
      if (info) {
        setUpdateInfo(info);
        setCheckState('found');
      } else {
        setCheckState('latest');
      }
    } catch {
      setCheckState('error');
    }
  };

  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white font-body flex flex-col">

      {/* Top glow */}
      <div className="w-full h-24 bg-gradient-to-b from-[#c8f500]/5 to-transparent pointer-events-none" style={{ marginBottom: '-6rem' }} />

      {/* Header */}
      <header className="relative z-10 px-4 pt-4 pb-3 border-b border-white/5 flex items-center gap-3">
        <button
          onClick={onBack}
          className="w-9 h-9 rounded-full bg-[#111] border border-white/10 hover:border-[#c8f500]/40 text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer flex items-center justify-center"
        >
          <ArrowLeft className="w-4 h-4" />
        </button>
        <div>
          <h1 className="text-lg font-heading text-white tracking-widest leading-none">PENGATURAN</h1>
          <p className="text-[9px] text-gray-600 uppercase tracking-widest">Settings</p>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-5 space-y-4">

        {/* App Info */}
        <div className="p-4 rounded-xl bg-[#0d0d0d] border border-white/5 flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-white">KyokoBeat</p>
            <p className="text-[10px] text-gray-500">Offline & Cloud Player</p>
          </div>
          <span className="text-[10px] text-gray-500 bg-white/5 px-2 py-1 rounded-lg">
            v{CURRENT_VERSION}
          </span>
        </div>

        {/* Update Checker */}
        <div className="p-4 rounded-xl bg-[#0d0d0d] border border-white/5 space-y-3">
          <p className="text-xs font-semibold text-white">Pembaruan Aplikasi</p>

          {/* Status info */}
          {checkState === 'latest' && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-green-500/10 border border-green-500/20">
              <CheckCircle className="w-4 h-4 text-green-400 flex-shrink-0" />
              <p className="text-xs text-green-400">Aplikasi sudah versi terbaru.</p>
            </div>
          )}

          {checkState === 'found' && updateInfo && (
            <div className="flex items-center justify-between p-3 rounded-lg bg-[#c8f500]/10 border border-[#c8f500]/30">
              <div>
                <p className="text-xs font-bold text-[#c8f500]">Update tersedia! v{updateInfo.version}</p>
                <p className="text-[10px] text-gray-400 mt-0.5">{updateInfo.changelog}</p>
              </div>
              <button
                onClick={() => setShowDialog(true)}
                className="ml-3 flex-shrink-0 flex items-center gap-1.5 px-3 py-1.5 bg-[#c8f500] text-black text-xs font-bold rounded-lg cursor-pointer hover:bg-[#d4ff00] transition-colors"
              >
                <Download className="w-3 h-3" />
                Update
              </button>
            </div>
          )}

          {checkState === 'error' && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-red-500/10 border border-red-500/20">
              <AlertCircle className="w-4 h-4 text-red-400 flex-shrink-0" />
              <p className="text-xs text-red-400">Gagal memeriksa update. Coba lagi.</p>
            </div>
          )}

          {/* Check button */}
          <button
            onClick={handleCheckUpdate}
            disabled={checkState === 'checking'}
            className="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl border border-white/10 bg-white/3 hover:border-[#c8f500]/30 hover:text-[#c8f500] text-gray-400 text-xs font-semibold transition-all cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${checkState === 'checking' ? 'animate-spin' : ''}`} />
            {checkState === 'checking' ? 'Memeriksa...' : 'Cek Update'}
          </button>
        </div>

      </div>

      {/* Update Dialog */}
      {showDialog && updateInfo && (
        <UpdateDialog
          info={updateInfo}
          onDismiss={() => setShowDialog(false)}
        />
      )}
    </div>
  );
}
