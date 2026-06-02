import React, { useState, useEffect } from 'react';
import FirstTimeScreen from './components/FirstTimeScreen';
import MainDashboard from './pages/MainDashboard';
import ResetPasswordPage from './components/ResetPasswordPage';
import UpdateDialog from './components/UpdateDialog';
import { ToastProvider, useToast } from './components/Toast';
import { getSongs, saveSongs, saveSetting, getSetting } from './lib/db';
import { scanDirectoryRecursive, verifyPermission, isFileSystemAccessSupported } from './lib/scanner';
import { isCapacitorActive, requestMobileStoragePermission, scanAllMobileStorage } from './lib/mobileScanner';
import { handleGoogleRedirect } from './lib/googleAuth';
import { checkForUpdate, UpdateInfo } from './lib/updater';

handleGoogleRedirect();

function AppContent() {
  const [hasSongsOrSkipped, setHasSongsOrSkipped] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);
  const [mobileScanning, setMobileScanning] = useState(false);
  const [mobileScanProgress, setMobileScanProgress] = useState({ scannedCount: 0, totalFiles: 0, currentFileName: '' });
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const { toast } = useToast();

  const isResetPasswordRoute = window.location.pathname === '/reset-password';

  useEffect(() => {
    if (isResetPasswordRoute) {
      setLoading(false);
      return;
    }
    checkFirstTimeStatus();

    // Cek update hanya di Android
    if (isCapacitorActive()) {
      checkForUpdate().then((info) => {
        if (info) setUpdateInfo(info);
      });
    }
  }, []);

  const checkFirstTimeStatus = async () => {
    try {
      const songs = await getSongs();
      const skipFirstTime = await getSetting('skipFirstTime');
      if (songs.length > 0 || skipFirstTime === 'true') {
        setHasSongsOrSkipped(true);
      } else {
        setHasSongsOrSkipped(false);
      }
    } catch (e) {
      console.error('Error checking IndexedDB status:', e);
      setHasSongsOrSkipped(false);
    } finally {
      setLoading(false);
    }
  };

  const handleSelectFolder = async () => {
    try {
      if (!isFileSystemAccessSupported()) {
        toast('Browser Anda tidak mendukung scanning folder lokal', 'error');
        return;
      }
      const dirHandle = await (window as any).showDirectoryPicker();
      toast('Menghubungkan folder musik...', 'info');
      await saveSetting('rootDirectoryHandle', dirHandle);
      const permitted = await verifyPermission(dirHandle, false);
      if (!permitted) { toast('Izin akses folder ditolak', 'error'); return; }
      toast('Memulai scanning file musik. Mohon tunggu...', 'info');
      const songs = await scanDirectoryRecursive(dirHandle);
      if (songs.length > 0) {
        await saveSongs(songs);
        await saveSetting('skipFirstTime', 'true');
        toast(`Berhasil mendeteksi ${songs.length} lagu! Selamat menikmati.`, 'success');
        setHasSongsOrSkipped(true);
      } else {
        toast('Tidak ada file audio terdeteksi di folder tersebut.', 'info');
        await saveSetting('skipFirstTime', 'true');
        setHasSongsOrSkipped(true);
      }
    } catch (err: any) {
      if (err.name !== 'AbortError') toast('Gagal memindai folder: ' + err.message, 'error');
    }
  };

  const handleSelectMobileStorage = async () => {
    setMobileScanning(true);
    try {
      const hasPermission = await requestMobileStoragePermission();
      if (!hasPermission) { toast('Izin penyimpanan ditolak.', 'error'); setMobileScanning(false); return; }
      toast('Memulai pemindaian penyimpanan internal ponsel Anda...', 'info');
      const songs = await scanAllMobileStorage((progress) => setMobileScanProgress(progress));
      if (songs.length > 0) {
        await saveSongs(songs);
        await saveSetting('skipFirstTime', 'true');
        toast(`Berhasil mendeteksi ${songs.length} lagu dari HP Anda!`, 'success');
        setHasSongsOrSkipped(true);
      } else {
        toast('Tidak ada file lagu yang ditemukan.', 'info');
        await saveSetting('skipFirstTime', 'true');
        setHasSongsOrSkipped(true);
      }
    } catch (e: any) {
      toast('Terjadi kesalahan saat memindai HP: ' + e.message, 'error');
    } finally {
      setMobileScanning(false);
    }
  };

  const handleUseCloudOnly = async () => {
    await saveSetting('skipFirstTime', 'true');
    toast('Memasuki mode Cloud Streaming', 'success');
    setHasSongsOrSkipped(true);
  };

  if (isResetPasswordRoute) return <ResetPasswordPage />;

  if (loading) {
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex flex-col items-center justify-center text-white">
        <div className="w-10 h-10 border-4 border-[#c8f500] border-t-transparent rounded-full animate-spin mb-4"></div>
        <p className="text-sm font-semibold text-gray-400 font-body uppercase tracking-wider">Menyiapkan KyokoBeat...</p>
      </div>
    );
  }

  if (mobileScanning) {
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex flex-col items-center justify-center text-white p-6 font-body">
        <div className="p-4 rounded-2xl bg-[#111] border border-[#c8f500]/20 max-w-md w-full text-center space-y-4">
          <div className="w-12 h-12 border-4 border-[#c8f500] border-t-transparent rounded-full animate-spin mx-auto"></div>
          <div>
            <h3 className="text-lg font-bold text-[#c8f500] uppercase tracking-wider">MEMINDAI PENYIMPANAN HP</h3>
            <p className="text-xs text-gray-400 mt-1">Mendeteksi lagu secara otomatis dari folder Musik & Download...</p>
          </div>
          <div className="bg-[#0a0a0a] p-3 rounded-lg border border-white/5 text-[10px] text-gray-500 truncate">
            File: {mobileScanProgress.currentFileName || 'Membaca direktori...'}
          </div>
          <div className="flex justify-between items-center text-xs text-gray-400">
            <span>Progress:</span>
            <span>{mobileScanProgress.scannedCount} Lagu Ditemukan</span>
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
      {hasSongsOrSkipped ? (
        <MainDashboard />
      ) : (
        <FirstTimeScreen
          onSelectFolder={handleSelectFolder}
          onSelectMobileStorage={handleSelectMobileStorage}
          onUseCloudOnly={handleUseCloudOnly}
        />
      )}
      {updateInfo && (
        <UpdateDialog info={updateInfo} onDismiss={() => setUpdateInfo(null)} />
      )}
    </>
  );
}

export default function App() {
  return (
    <ToastProvider>
      <AppContent />
    </ToastProvider>
  );
}
