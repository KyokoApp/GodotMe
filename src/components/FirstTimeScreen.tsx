import React, { useState, useEffect } from 'react';
import { FolderOpen, Music, ShieldCheck, Zap, Cloud, Smartphone } from 'lucide-react';
import { isFileSystemAccessSupported } from '../lib/scanner';
import { isCapacitorActive } from '../lib/mobileScanner';

interface FirstTimeScreenProps {
  onSelectFolder: () => void;
  onSelectMobileStorage: () => void;
  onUseCloudOnly: () => void;
}

export default function FirstTimeScreen({ onSelectFolder, onSelectMobileStorage, onUseCloudOnly }: FirstTimeScreenProps) {
  const supported = isFileSystemAccessSupported();
  const isMobileApp = isCapacitorActive();

  return (
    <div className="min-h-screen flex flex-col justify-center items-center p-6 bg-[#0a0a0a] text-white">
      {/* Glow background */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-72 h-72 rounded-full bg-[#c8f500]/5 blur-[100px] pointer-events-none"></div>

      <div className="w-full max-w-md text-center z-10 space-y-8 animate-fade-in">
        {/* Logo */}
        <div className="space-y-2">
          <div className="inline-flex items-center justify-center p-4 rounded-2xl bg-[#111] border border-[#c8f500]/20 shadow-[0_0_30px_rgba(200,245,0,0.1)] mb-4">
            <Music className="w-12 h-12 text-[#c8f500] animate-pulse" />
          </div>
          <h1 className="text-6xl font-heading text-[#c8f500] tracking-widest">KyokoBeat</h1>
          <p className="text-xs text-gray-400 font-body uppercase tracking-wider">Aplikasi Musik Offline & Cloud</p>
        </div>

        {/* Benefits Cards */}
        <div className="space-y-3 font-body text-left">
          <div className="flex gap-4 p-4 rounded-xl bg-[#111] border border-white/5">
            <div className="p-2 rounded-lg bg-[#0a0a0a] text-[#c8f500]">
              <Zap className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-white">Deteksi Musik Otomatis</h3>
              <p className="text-xs text-gray-400 mt-1">
                {isMobileApp 
                  ? 'Otomatis memindai folder musik & download di seluruh penyimpanan ponsel Anda.' 
                  : 'Cukup pilih folder musik sekali, KyokoBeat akan otomatis mendeteksi seluruh file audio.'}
              </p>
            </div>
          </div>

          <div className="flex gap-4 p-4 rounded-xl bg-[#111] border border-white/5">
            <div className="p-2 rounded-lg bg-[#0a0a0a] text-[#c8f500]">
              <ShieldCheck className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-white">100% Aman & Privat</h3>
              <p className="text-xs text-gray-400 mt-1">Lagu Anda diputar langsung dari perangkat lokal Anda. Data metadata disimpan aman di IndexedDB browser Anda.</p>
            </div>
          </div>
        </div>

        {/* Support Alert / Actions */}
        <div className="space-y-4 pt-4">
          {isMobileApp ? (
            <div className="space-y-3">
              <button
                onClick={onSelectMobileStorage}
                className="w-full py-4 bg-[#c8f500] text-black font-semibold font-body rounded-xl shadow-[0_0_20px_rgba(200,245,0,0.3)] hover:shadow-[0_0_30px_rgba(200,245,0,0.5)] transition-all duration-300 flex items-center justify-center gap-3 cursor-pointer text-base"
              >
                <Smartphone className="w-5 h-5" />
                Scan Penyimpanan HP Anda
              </button>
              
              <button
                onClick={onUseCloudOnly}
                className="w-full py-3 bg-[#0a0a0a] border border-[#c8f500]/40 text-[#c8f500] font-semibold font-body rounded-xl hover:bg-[#c8f500]/10 transition-all duration-300 flex items-center justify-center gap-2 cursor-pointer text-sm"
              >
                <Cloud className="w-4 h-4" />
                Gunakan Cloud Streaming
              </button>
            </div>
          ) : supported ? (
            <div className="space-y-3">
              <button
                onClick={onSelectFolder}
                className="w-full py-4 bg-[#c8f500] text-black font-semibold font-body rounded-xl shadow-[0_0_20px_rgba(200,245,0,0.3)] hover:shadow-[0_0_30px_rgba(200,245,0,0.5)] transition-all duration-300 flex items-center justify-center gap-3 cursor-pointer text-base"
              >
                <FolderOpen className="w-5 h-5" />
                Pilih Folder Musik Lokal
              </button>
              
              <button
                onClick={onUseCloudOnly}
                className="w-full py-3 bg-[#0a0a0a] border border-[#c8f500]/40 text-[#c8f500] font-semibold font-body rounded-xl hover:bg-[#c8f500]/10 transition-all duration-300 flex items-center justify-center gap-2 cursor-pointer text-sm"
              >
                <Cloud className="w-4 h-4" />
                Masuk dengan Cloud Streaming
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-left font-body">
                <p className="text-xs text-red-400 leading-relaxed">
                  Browser Anda tidak mendukung File System Access API secara penuh (biasanya terjadi di iOS, Safari, atau browser mobile).
                </p>
                <p className="text-xs text-gray-400 mt-2 leading-relaxed">
                  Jangan khawatir! Anda masih bisa menikmati musik streaming berkualitas tinggi dari cloud kami secara instan, atau install aplikasi native kami dengan Capacitor.
                </p>
              </div>

              <button
                onClick={onUseCloudOnly}
                className="w-full py-4 bg-[#c8f500] text-black font-semibold font-body rounded-xl shadow-[0_0_20px_rgba(200,245,0,0.3)] hover:shadow-[0_0_30px_rgba(200,245,0,0.5)] transition-all duration-300 flex items-center justify-center gap-3 cursor-pointer text-base"
              >
                <Cloud className="w-5 h-5" />
                Mulai Cloud Streaming
              </button>
            </div>
          )}

          <p className="text-[10px] text-gray-500 font-body">
            Dengan melanjutkan, Anda memberikan izin kepada aplikasi untuk membaca file audio di folder yang Anda pilih.
          </p>
        </div>
      </div>
    </div>
  );
}
