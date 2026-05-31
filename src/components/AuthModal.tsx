import React, { useState } from 'react';
import { X, Mail, Lock, User, LogIn, UserPlus } from 'lucide-react';
import supabase from '../lib/supabase';
import { signInWithGoogle } from '../lib/googleAuth';
import { useToast } from './Toast';

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAuthSuccess: () => void;
}

export default function AuthModal({ isOpen, onClose, onAuthSuccess }: AuthModalProps) {
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const { toast } = useToast();

  if (!isOpen) return null;

  const handleEmailAuth = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) {
      toast('Email dan password harus diisi', 'error');
      return;
    }
    if (password.length < 6) {
      toast('Password minimal 6 karakter', 'error');
      return;
    }

    setLoading(true);
    try {
      if (isSignUp) {
        const { data, error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        toast('Pendaftaran berhasil! Silakan periksa email Anda atau langsung masuk.', 'success');
        setIsSignUp(false);
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        toast('Masuk berhasil!', 'success');
        onAuthSuccess();
        onClose();
      }
    } catch (err: any) {
      console.error(err);
      toast(err.message || 'Terjadi kesalahan autentikasi', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleGoogleLogin = () => {
    signInWithGoogle('KyokoBeat');
    // We close the modal, the redirect handles session completion
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <div className="relative w-full max-w-md p-6 rounded-xl bg-[#111] border border-[#c8f500]/30 shadow-[0_0_30px_rgba(200,245,0,0.15)] animate-scale-up">
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-gray-400 hover:text-[#c8f500] transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Title */}
        <h2 className="text-3xl font-heading text-[#c8f500] tracking-wider mb-2">
          {isSignUp ? 'DAFTAR AKUN' : 'MASUK KE KYOKOBEAT'}
        </h2>
        <p className="text-xs text-gray-400 font-body mb-6">
          {isSignUp 
            ? 'Buat akun untuk mencadangkan playlist dan lagu favorit Anda ke cloud.' 
            : 'Masuk untuk sinkronisasi playlist dan lagu favorit Anda di semua perangkat.'}
        </p>

        {/* Form */}
        <form onSubmit={handleEmailAuth} className="space-y-4 font-body">
          <div>
            <label className="block text-xs text-gray-400 mb-1">Email</label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
              <input
                type="email"
                placeholder="nama@email.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs text-gray-400 mb-1">Password</label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
              <input
                type="password"
                placeholder="••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 bg-[#0a0a0a] border border-gray-800 rounded-lg text-white text-sm focus:outline-none focus:border-[#c8f500] transition-colors"
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 bg-[#c8f500] text-black font-semibold rounded-lg hover:shadow-[0_0_15px_rgba(200,245,0,0.4)] transition-all duration-300 flex items-center justify-center gap-2 cursor-pointer"
          >
            {loading ? (
              <span className="w-5 h-5 border-2 border-black border-t-transparent rounded-full animate-spin"></span>
            ) : isSignUp ? (
              <>
                <UserPlus className="w-4 h-4" /> Daftar Sekarang
              </>
            ) : (
              <>
                <LogIn className="w-4 h-4" /> Masuk Akun
              </>
            )}
          </button>
        </form>

        {/* Divider */}
        <div className="relative my-6 text-center">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-gray-800"></div>
          </div>
          <span className="relative px-3 bg-[#111] text-xs text-gray-500 font-body uppercase">atau</span>
        </div>

        {/* Google Sign-in */}
        <button
          onClick={handleGoogleLogin}
          className="w-full py-2.5 bg-[#0a0a0a] border border-[#c8f500]/40 text-[#c8f500] font-medium rounded-lg hover:bg-[#c8f500]/10 transition-colors flex items-center justify-center gap-2 font-body cursor-pointer"
        >
          <svg className="w-4 h-4 fill-current" viewBox="0 0 24 24">
            <path d="M12.24 10.285V14.4h6.887c-.648 2.41-2.519 4.114-5.136 4.114A5.99 5.99 0 018 12.527a5.99 5.99 0 015.99-5.99c2.477 0 4.595 1.49 5.433 3.614l3.864-3A11.962 11.962 0 0013.99 2C7.37 2 2 7.37 2 13.99s5.37 11.99 11.99 11.99c7.227 0 11.24-5.08 11.24-11.24a10.4 10.4 0 00-.232-2.455H12.24z"/>
          </svg>
          Masuk dengan Google
        </button>

        {/* Toggle Sign Up / Sign In */}
        <div className="mt-6 text-center font-body text-xs text-gray-400">
          {isSignUp ? 'Sudah punya akun?' : 'Belum punya akun?'}{' '}
          <button
            onClick={() => setIsSignUp(!isSignUp)}
            className="text-[#c8f500] hover:underline font-semibold"
          >
            {isSignUp ? 'Masuk di sini' : 'Daftar di sini'}
          </button>
        </div>
      </div>
    </div>
  );
}
