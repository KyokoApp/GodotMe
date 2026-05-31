import React, { useState, useEffect } from 'react';
import { Cloud, CloudLightning, CloudOff, RefreshCw, User, LogOut, LogIn } from 'lucide-react';
import supabase from '../lib/supabase';
import { useToast } from './Toast';

interface CloudSyncIndicatorProps {
  user: any;
  onLoginClick: () => void;
  onLogoutSuccess: () => void;
  favorites: string[];
  playlists: any[];
  onSyncComplete: () => void;
}

export default function CloudSyncIndicator({
  user,
  onLoginClick,
  onLogoutSuccess,
  favorites,
  playlists,
  onSyncComplete
}: CloudSyncIndicatorProps) {
  const [syncing, setSyncing] = useState(false);
  const { toast } = useToast();

  const handleLogout = async () => {
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      toast('Keluar dari akun cloud', 'info');
      onLogoutSuccess();
    } catch (e: any) {
      toast(e.message || 'Gagal keluar', 'error');
    }
  };

  const handleSync = async () => {
    if (!user) {
      onLoginClick();
      return;
    }

    setSyncing(true);
    try {
      const token = (await supabase.auth.getSession()).data.session?.access_token;
      
      // 1. Sync Favorites to Cloud
      // Get current cloud favorites first
      const favRes = await fetch('/api/favorites', {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      const cloudFavs = await favRes.json();
      
      // Upload local favorites that are not on cloud
      // Since local favorites are just song IDs, we'll look up details from our local IndexedDB or upload placeholders
      // For simplicity, let's sync local favorites
      // Wait, we can post any new favorites to the API
      // Let's do that!
      for (const songId of favorites) {
        const alreadyOnCloud = cloudFavs.some((f: any) => f.song_id === songId);
        if (!alreadyOnCloud) {
          await fetch('/api/favorites', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
              song_id: songId,
              title: songId.split('/').pop() || 'Local Song',
              artist: 'Local Artist',
              album: 'Local Album'
            })
          });
        }
      }

      // 2. Sync Playlists to Cloud
      const plRes = await fetch('/api/playlists', {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      const cloudPlaylists = await plRes.json();

      for (const pl of playlists) {
        const alreadyOnCloud = cloudPlaylists.some((cp: any) => cp.name === pl.name);
        if (!alreadyOnCloud) {
          // Create playlist on cloud
          const createRes = await fetch('/api/playlists', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
              name: pl.name,
              description: pl.description || 'Synced Playlist'
            })
          });
          const cloudPl = await createRes.json();

          if (cloudPl && cloudPl.id) {
            // Add tracks to this cloud playlist
            for (const songId of pl.songIds) {
              await fetch('/api/playlist-tracks', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({
                  playlist_id: cloudPl.id,
                  song_id: songId,
                  title: songId.split('/').pop() || 'Local Track'
                })
              });
            }
          }
        }
      }

      toast('Sinkronisasi cloud berhasil diselesaikan!', 'success');
      onSyncComplete();
    } catch (e: any) {
      console.error(e);
      toast('Gagal melakukan sinkronisasi cloud: ' + e.message, 'error');
    } finally {
      setSyncing(false);
    }
  };

  return (
    <div className="flex items-center gap-3 p-2 px-3 rounded-full bg-[#111] border border-[#c8f500]/10 text-white font-body text-xs">
      {user ? (
        <>
          <div className="flex items-center gap-1.5 text-[#c8f500]">
            <Cloud className="w-4 h-4 animate-pulse" />
            <span className="font-semibold max-w-[80px] sm:max-w-[120px] truncate" title={user.email}>
              {user.email.split('@')[0].toUpperCase()}
            </span>
          </div>

          <div className="h-4 w-[1px] bg-gray-800"></div>

          {/* Sync Button */}
          <button
            onClick={handleSync}
            disabled={syncing}
            className="flex items-center gap-1 text-gray-400 hover:text-white transition-colors cursor-pointer"
            title="Sinkronisasi ke Cloud"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${syncing ? 'animate-spin text-[#c8f500]' : ''}`} />
            <span className="hidden sm:inline">Sinkronisasi</span>
          </button>

          <div className="h-4 w-[1px] bg-gray-800"></div>

          {/* Logout */}
          <button
            onClick={handleLogout}
            className="text-gray-400 hover:text-red-500 transition-colors cursor-pointer"
            title="Keluar Akun"
          >
            <LogOut className="w-3.5 h-3.5" />
          </button>
        </>
      ) : (
        <>
          <div className="flex items-center gap-1.5 text-gray-500">
            <CloudOff className="w-4 h-4" />
            <span>CLOUD OFFLINE</span>
          </div>
          <div className="h-4 w-[1px] bg-gray-800"></div>
          <button
            onClick={onLoginClick}
            className="flex items-center gap-1 text-[#c8f500] font-semibold hover:underline cursor-pointer"
          >
            <LogIn className="w-3.5 h-3.5" />
            <span>MASUK</span>
          </button>
        </>
      )}
    </div>
  );
}
