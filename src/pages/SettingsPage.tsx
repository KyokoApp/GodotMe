import React from 'react';
import { ArrowLeft } from 'lucide-react';

interface SettingsPageProps {
  onBack: () => void;
}

export default function SettingsPage({ onBack }: SettingsPageProps) {
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

      <div className="flex-1 overflow-y-auto px-4 py-5 space-y-6">

        {/* App Info */}
        <div className="p-4 rounded-xl bg-[#0d0d0d] border border-white/5 flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-white">KyokoBeat</p>
            <p className="text-[10px] text-gray-600">Offline & Cloud Player</p>
          </div>
          <span className="text-[10px] text-gray-600 bg-white/5 px-2 py-1 rounded-lg">v1.1.2</span>
        </div>

        {/* Placeholder untuk fitur settings ke depan */}
        <div className="p-6 rounded-xl bg-[#0d0d0d] border border-white/5 text-center">
          <p className="text-2xl mb-2">⚙️</p>
          <p className="text-xs text-gray-500">Fitur pengaturan akan hadir di sini.</p>
        </div>

      </div>
    </div>
  );
}
