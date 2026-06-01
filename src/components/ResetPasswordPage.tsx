import React, { useState, useEffect } from 'react';
import { Lock, CheckCircle, AlertCircle, RefreshCw, Eye, EyeOff } from 'lucide-react';
import supabase from '../lib/supabase';
import { useToast } from './Toast';

export default function ResetPasswordPage() {
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState<'idle' | 'success' | 'error' | 'invalid'>('idle');
  const [sessionReady, setSessionReady] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    // Supabase mengirim token via URL hash (#access_token=...&type=recovery)
    // onAuthStateChange akan otomatis menangkap session dari hash ini
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event: string, session: any) => {
      if (event === 'PASSWORD_RECOVERY') {
        setSessionReady(true);
      }
    });

    // Fallback: cek session yang sudah ada (kalau sudah ter-parse)
    supabase.auth.getSession().then(({ data: { session } }: any) => {
      if (session) setSessionReady(true);
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleReset = async () => {
    if (!password || !confirmPassword) {
      toast('Isi semua kolom terlebih dahulu', 'error');
      return;
    }
    if (password.length < 6) {
      toast('Password minimal 6 karakter', 'error');
      return;
    }
    if (password !== confirmPassword) {
      toast('Konfirmasi password tidak cocok', 'error');
      return;
    }

    setLoading(true);
    try {
      const { error } = await supabase.auth.updateUser({ password });
      if (error) throw error;
      setStatus('success');
      toast('Password berhasil diubah!', 'success');
    } catch (err: any) {
      console.error(err);
      setStatus('error');
      toast(err.message || 'Gagal mengubah password', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleGoHome = () => {
    // Redirect ke root, hapus hash dari URL
    window.location.href = '/';
  };

  return (
    <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center p-4">
      {/* Background glow effect */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-[#c8f500]/5 rounded-full blur-[120px]" />
      </div>

      <div className="relative w-full max-w-md">
        {/* Logo / Branding */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-heading text-[#c8f500] tracking-widest">KYOKOBEAT</h1>
          <p className="text-xs text-gray-500 font-body mt-1 uppercase tracking-wider">Music Player</p>
        </div>

        <div className="p-6 rounded-xl bg-[#111] border border-[#c8f500]/30 shadow-[0_0_40px_rgba(200,245,0,0.1)]">

          {/* SUCCESS STATE */}
          {status === 'success' ? (
            <div className="text-center space-y-4">
              <div className="flex justify-center">
                <div className="w-16 h-16 rounded-full bg-green-500/10 border border-green-500/30 flex items-center justify-center">
                  <CheckCircle className="w-8 h-8 text-green-400" />
                </div>
              </div>
              <div>
                <h2 className="text-2xl font-heading text-[#c8f500] tracking-wider">SANDI DIPERBARUI!</h2>
                <p className="text-sm text-gray-400 font-body mt-2">
                  Password kamu berhasil diubah. Silakan masuk dengan password baru.
                </p>
              </div>
              <button
                onClick={handleGoHome}
                className="w-full py-3 bg-[#c8f500] text-black font-semibold rounded-lg hover:shadow-[0_0_15px_rgba(200,245,0,0.4)] transition-all duration-300 font-body cursor-pointer"
              >
                Kembali ke Beranda
              </button>
            </div>
          ) : !sessionReady ? (
            /* LOADING SESSION STATE */
            <div className="text-center space-y-4 py-4">
              <div className="w-10 h-10 border-4 border-[#c8f500] border-t-transparent rounded-full animate-spin mx-auto" />
              <div>
                <h2 className="text-xl font-heading text-[#c8f500] tracking-wider">MEMVERIFIKASI LINK</h2>
                <p className="text-xs text-gray-500 font-body mt-2">
                  Sedang memvalidasi link reset sandi kamu...
                </p>
              </div>
              <p className="text-xs text-gray-600 font-body">
                Jika halaman ini tidak berubah, link mungkin sudah kadaluarsa.{' '}
                <button onClick={handleGoHome} className="text-[#c8f500]/70 hover:text-[#c8f500] underline cursor-pointer">
                  Kembali ke beranda
                </button>
              </p>
            </div>
          ) : (
            /* FORM STATE */
            <>
              <div className="mb-6">
                <h2 className="text-2xl font-heading text-[#c8f500] tracking-wider">BUAT SANDI BARU</h2>
                <p className="text-xs text-gray-400 font-body mt-1">
                  Masukkan password baru kamu di bawah ini.
                </p>
              </div>

              <div className="space-y-4 font-body">
                {/* Password field */}
                <div>
                  <label className="block text-xs text-gray-400 mb-1">Password Baru</label>
                  <div className="relative">
                    <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
                    <input
                      type={showPassword ? 'text' : 'password'}
                      placeholder="Minimal 6 karakter"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      onKeyDown={(e) => e.key === 'Enter' && handleReset()}
                      className="w-full pl-10 pr-10 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword(!showPassword)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-[#c8f500] transition-colors cursor-pointer"
                    >
                      {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                {/* Confirm password field */}
                <div>
                  <label className="block text-xs text-gray-400 mb-1">Konfirmasi Password</label>
                  <div className="relative">
                    <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
                    <input
                      type={showConfirm ? 'text' : 'password'}
                      placeholder="Ulangi password baru"
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      onKeyDown={(e) => e.key === 'Enter' && handleReset()}
                      className="w-full pl-10 pr-10 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowConfirm(!showConfirm)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-[#c8f500] transition-colors cursor-pointer"
                    >
                      {showConfirm ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                {/* Password match indicator */}
                {confirmPassword.length > 0 && (
                  <div className={`flex items-center gap-2 text-xs ${password === confirmPassword ? 'text-green-400' : 'text-red-400'}`}>
                    {password === confirmPassword
                      ? <><CheckCircle className="w-3.5 h-3.5" /> Password cocok</>
                      : <><AlertCircle className="w-3.5 h-3.5" /> Password tidak cocok</>
                    }
                  </div>
                )}

                {/* Submit button */}
                <button
                  onClick={handleReset}
                  disabled={loading}
                  className="w-full py-3 bg-[#c8f500] text-black font-semibold rounded-lg hover:shadow-[0_0_15px_rgba(200,245,0,0.4)] transition-all duration-300 flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer mt-2"
                >
                  {loading ? (
                    <span className="w-5 h-5 border-2 border-black border-t-transparent rounded-full animate-spin" />
                  ) : (
                    <><RefreshCw className="w-4 h-4" /> Simpan Password Baru</>
                  )}
                </button>

                <button
                  onClick={handleGoHome}
                  className="w-full py-2 text-xs text-gray-400 hover:text-[#c8f500] transition-colors cursor-pointer"
                >
                  ← Batal, kembali ke beranda
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
