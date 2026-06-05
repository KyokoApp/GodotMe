import { LocalSong } from './db';

type AudioStateCallback = (state: {
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  currentSong: LocalSong | null;
  isMuted: boolean;
}) => void;

// ── Capacitor plugin bridge untuk MusicNotificationPlugin ──
async function callMusicNotification(method: string, options: Record<string, unknown> = {}) {
  try {
    const { registerPlugin } = await import('@capacitor/core');
    const MusicNotification = registerPlugin<any>('MusicNotification');
    return await MusicNotification[method](options);
  } catch (e) {
    // Plugin belum tersedia (web browser), ignore
  }
}

class AudioManager {
  private audio: HTMLAudioElement;
  private audioContext: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private sourceNode: MediaElementAudioSourceNode | null = null;
  private currentSong: LocalSong | null = null;
  private callbacks: Set<AudioStateCallback> = new Set();
  private lastCrossOrigin: boolean = false;

  constructor() {
    this.audio = new Audio();
    this.audio.preload = 'auto';

    this.audio.addEventListener('play', () => {
      this.notifyState();
      this.syncMediaSession();
    });
    this.audio.addEventListener('pause', () => {
      this.notifyState();
      this.syncMediaSession();
    });
    this.audio.addEventListener('timeupdate', () => {
      this.notifyState();
      this.syncMediaSessionPosition();
    });
    this.audio.addEventListener('durationchange', () => this.notifyState());
    this.audio.addEventListener('volumechange', () => this.notifyState());
    this.audio.addEventListener('ended', () => {
      this.notifyState();
      this.handleTrackEnded();
    });
    this.audio.addEventListener('error', (e) => {
      console.error('Audio element error:', this.audio.error);
    });

    // Listen for native notification actions (play/pause/next/prev dari lockscreen)
    this.setupNativeNotificationListeners();
  }

  public onTrackEnded: (() => void) | null = null;
  public onPrevTrack: (() => void) | null = null;

  private handleTrackEnded() {
    if (this.onTrackEnded) {
      this.onTrackEnded();
    }
  }

  // Check if running in Capacitor native app (Android/iOS)
  private isNative(): boolean {
    return typeof window !== 'undefined' &&
      (window as any).Capacitor !== undefined &&
      (window as any).Capacitor.isNativePlatform?.() === true;
  }

  // Setup listener untuk action dari native notification (next/prev/play/pause)
  private setupNativeNotificationListeners() {
    if (typeof window === 'undefined') return;
    window.addEventListener('kyokobeat:notification:play', () => {
      this.audio.play().catch(() => {});
    });
    window.addEventListener('kyokobeat:notification:pause', () => {
      this.audio.pause();
    });
    window.addEventListener('kyokobeat:notification:next', () => {
      if (this.onTrackEnded) this.onTrackEnded();
    });
    window.addEventListener('kyokobeat:notification:prev', () => {
      if (this.onPrevTrack) this.onPrevTrack();
    });
  }

  // Lazily initialize Web Audio API (web only, not native)
  private initAudioContext() {
    if (this.audioContext) return;
    if (this.isNative()) return; // Skip Web Audio API on native — causes issues with Android WebView

    try {
      this.audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
      this.analyser = this.audioContext.createAnalyser();
      this.analyser.fftSize = 256;

      this.sourceNode = this.audioContext.createMediaElementSource(this.audio);
      this.sourceNode.connect(this.analyser);
      this.analyser.connect(this.audioContext.destination);
    } catch (e) {
      console.warn('Web Audio API not fully supported:', e);
    }
  }

  // Ensure AudioContext is running
  private async ensureAudioContextRunning() {
    if (!this.audioContext) return;
    try {
      if (this.audioContext.state === 'suspended') {
        await this.audioContext.resume();
      }
      if (this.audioContext.state === 'closed') {
        this.audioContext = null;
        this.analyser = null;
        this.sourceNode = null;
        this.initAudioContext();
        if (this.audioContext && (this.audioContext as AudioContext).state === 'suspended') {
          await (this.audioContext as AudioContext).resume();
        }
      }
    } catch (e) {
      console.warn('Could not resume AudioContext:', e);
    }
  }

  // ─── Media Session API (web browser) ──────────────────────────────────────

  private updateMediaSession(song: LocalSong) {
    if (!('mediaSession' in navigator)) return;

    const artwork: MediaImage[] = [];
    if (song.cover) {
      artwork.push({ src: song.cover, sizes: '512x512', type: 'image/jpeg' });
    }

    navigator.mediaSession.metadata = new MediaMetadata({
      title: song.title || 'Unknown Title',
      artist: song.artist || 'Unknown Artist',
      album: song.album || 'KyokoBeat',
      artwork,
    });

    navigator.mediaSession.setActionHandler('play', () => {
      this.audio.play().catch(() => {});
      this.syncMediaSession();
    });
    navigator.mediaSession.setActionHandler('pause', () => {
      this.audio.pause();
      this.syncMediaSession();
    });
    navigator.mediaSession.setActionHandler('previoustrack', () => {
      if (this.onPrevTrack) this.onPrevTrack();
    });
    navigator.mediaSession.setActionHandler('nexttrack', () => {
      if (this.onTrackEnded) this.onTrackEnded();
    });
    navigator.mediaSession.setActionHandler('seekto', (details) => {
      if (details.seekTime !== undefined) {
        this.audio.currentTime = details.seekTime;
        this.syncMediaSessionPosition();
      }
    });
    navigator.mediaSession.setActionHandler('seekbackward', (details) => {
      this.audio.currentTime = Math.max(0, this.audio.currentTime - (details.seekOffset ?? 10));
      this.syncMediaSessionPosition();
    });
    navigator.mediaSession.setActionHandler('seekforward', (details) => {
      this.audio.currentTime = Math.min(
        this.audio.duration || 0,
        this.audio.currentTime + (details.seekOffset ?? 10)
      );
      this.syncMediaSessionPosition();
    });

    this.syncMediaSession();
  }

  private syncMediaSession() {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.playbackState = this.audio.paused ? 'paused' : 'playing';
  }

  private syncMediaSessionPosition() {
    if (!('mediaSession' in navigator)) return;
    if (!this.audio.duration || isNaN(this.audio.duration)) return;
    try {
      navigator.mediaSession.setPositionState({
        duration: this.audio.duration,
        playbackRate: this.audio.playbackRate,
        position: this.audio.currentTime,
      });
    } catch (_) {}
  }

  // ─── Native Android Notification (via MusicNotificationPlugin) ────────────

  private async updateNativeNotification(song: LocalSong) {
    if (!this.isNative()) return;
    await callMusicNotification('showNotification', {
      title: song.title || 'Unknown Title',
      artist: song.artist || 'Unknown Artist',
      album: song.album || 'KyokoBeat',
      cover: song.cover || '',
      isPlaying: !this.audio.paused,
      duration: Math.floor((this.audio.duration || song.duration || 0) * 1000),
      position: Math.floor(this.audio.currentTime * 1000),
    });
  }

  public async syncNativePlayState() {
    if (!this.isNative() || !this.currentSong) return;
    await callMusicNotification('updatePlaybackState', {
      isPlaying: !this.audio.paused,
      position: Math.floor(this.audio.currentTime * 1000),
    });
  }

  public async dismissNativeNotification() {
    if (!this.isNative()) return;
    await callMusicNotification('hideNotification', {});
  }

  // ──────────────────────────────────────────────────────────────────────────

  public subscribe(callback: AudioStateCallback) {
    this.callbacks.add(callback);
    this.notifyState();
    return () => {
      this.callbacks.delete(callback);
    };
  }

  private notifyState() {
    const state = {
      isPlaying: !this.audio.paused && !this.audio.ended,
      currentTime: this.audio.currentTime || 0,
      duration: this.audio.duration || this.currentSong?.duration || 0,
      volume: this.audio.volume,
      currentSong: this.currentSong,
      isMuted: this.audio.muted,
    };
    this.callbacks.forEach(cb => cb(state));
  }

  public async playSong(song: LocalSong) {
    const native = this.isNative();

    // Web Audio API only on browser, not native
    if (!native) {
      this.initAudioContext();
      await this.ensureAudioContextRunning();
    }

    try {
      let src = '';

      // On native Android/iOS: NEVER set crossOrigin for any URL
      if (native) {
        if (this.lastCrossOrigin) {
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
        }

        if (song.isCloud && song.audioUrl) {
          src = song.audioUrl;
        } else if (song.isDownloaded && song.audioUrl) {
          src = song.audioUrl;
        } else if (song.audioUrl) {
          src = song.audioUrl;
          if (src.startsWith('/storage/') || src.startsWith('/data/')) {
            try {
              const { Capacitor } = await import('@capacitor/core');
              src = Capacitor.convertFileSrc(song.audioUrl);
            } catch (e) {
              console.warn('Could not convert file src:', e);
            }
          }
        } else {
          const file = await song.fileHandle.getFile();
          src = URL.createObjectURL(file);
        }

        if (this.audio.src && this.audio.src.startsWith('blob:')) {
          URL.revokeObjectURL(this.audio.src);
        }

        this.currentSong = song;
        this.audio.src = src;
        this.audio.load();
        await this.audio.play();

        // ★ Tampilkan native notification di Android
        await this.updateNativeNotification(song);
        this.notifyState();
        return;
      }

      // === WEB BROWSER PATH (non-native) ===
      const needsCors = !!(song.isCloud || song.isDownloaded) && !!(song.audioUrl);

      if (song.isCloud && song.audioUrl) {
        src = song.audioUrl;
        this.audio.crossOrigin = 'anonymous';
        this.lastCrossOrigin = true;
      } else if (song.isDownloaded && song.audioUrl) {
        src = song.audioUrl;
        this.audio.crossOrigin = 'anonymous';
        this.lastCrossOrigin = true;
      } else if (song.audioUrl) {
        if (this.lastCrossOrigin) {
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
        }
        src = song.audioUrl;
      } else {
        if (this.lastCrossOrigin) {
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
        }
        const file = await song.fileHandle.getFile();
        src = URL.createObjectURL(file);
      }

      if (this.audio.src && this.audio.src.startsWith('blob:')) {
        URL.revokeObjectURL(this.audio.src);
      }

      this.currentSong = song;
      this.audio.src = src;
      this.audio.load();

      try {
        await this.audio.play();
      } catch (playError: any) {
        if (needsCors) {
          console.warn('Play with CORS failed, retrying without CORS...', playError);
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
          this.audio.src = src;
          this.audio.load();
          await this.audio.play();
        } else {
          throw playError;
        }
      }

      this.updateMediaSession(song);
      this.notifyState();
    } catch (error) {
      console.error('Failed to play song:', error);
      throw error;
    }
  }

  public async togglePlay() {
    if (!this.currentSong) return;

    if (!this.isNative()) {
      this.initAudioContext();
      await this.ensureAudioContextRunning();
    }

    if (this.audio.paused) {
      await this.audio.play();
    } else {
      this.audio.pause();
    }

    // ★ Update state di native notification
    if (this.isNative()) {
      await this.syncNativePlayState();
    }

    this.notifyState();
  }

  public seek(time: number) {
    if (!this.currentSong) return;
    this.audio.currentTime = time;
    this.notifyState();
  }

  public setVolume(volume: number) {
    const clamped = Math.max(0, Math.min(1, volume));
    this.audio.volume = clamped;
    this.audio.muted = clamped === 0;
    this.notifyState();
  }

  public toggleMute() {
    this.audio.muted = !this.audio.muted;
    this.notifyState();
  }

  public getAnalyserData(): Uint8Array | null {
    if (!this.analyser || this.audio.paused) return null;

    try {
      const bufferLength = this.analyser.frequencyBinCount;
      const dataArray = new Uint8Array(bufferLength);
      this.analyser.getByteFrequencyData(dataArray);
      return dataArray;
    } catch (e) {
      return null;
    }
  }

  public getCurrentSong() {
    return this.currentSong;
  }

  public isPlaying() {
    return !this.audio.paused && !this.audio.ended;
  }
}

export const audioManager = new AudioManager();
export default audioManager;
