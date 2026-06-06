import { LocalSong } from './db';

type AudioStateCallback = (state: {
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  currentSong: LocalSong | null;
  isMuted: boolean;
}) => void;

// Lazy-load @jofr/capacitor-media-session only on native
let MediaSessionPlugin: any = null;
const getMediaSessionPlugin = async () => {
  if (MediaSessionPlugin) return MediaSessionPlugin;
  try {
    const mod = await import('@jofr/capacitor-media-session');
    MediaSessionPlugin = mod.MediaSession;
    return MediaSessionPlugin;
  } catch {
    return null;
  }
};

class AudioManager {
  private audio: HTMLAudioElement;
  private audioContext: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private sourceNode: MediaElementAudioSourceNode | null = null;
  private currentSong: LocalSong | null = null;
  private callbacks: Set<AudioStateCallback> = new Set();
  private lastCrossOrigin: boolean = false;
  private positionTimer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    this.audio = new Audio();
    this.audio.preload = 'auto';

    this.audio.addEventListener('play', () => {
      this.notifyState();
      this.syncPlaybackState('playing');
      this.startPositionTimer();
    });
    this.audio.addEventListener('pause', () => {
      this.notifyState();
      this.syncPlaybackState('paused');
      this.stopPositionTimer();
    });
    this.audio.addEventListener('timeupdate', () => this.notifyState());
    this.audio.addEventListener('durationchange', () => this.notifyState());
    this.audio.addEventListener('volumechange', () => this.notifyState());
    this.audio.addEventListener('ended', () => {
      this.notifyState();
      this.syncPlaybackState('stopped');
      this.stopPositionTimer();
      this.handleTrackEnded();
    });
    this.audio.addEventListener('error', () => {
      console.error('Audio element error:', this.audio.error);
    });
  }

  public onTrackEnded: (() => void) | null = null;
  public onPrevTrack: (() => void) | null = null;

  private handleTrackEnded() {
    if (this.onTrackEnded) this.onTrackEnded();
  }

  private isNative(): boolean {
    return typeof window !== 'undefined' &&
      (window as any).Capacitor !== undefined &&
      (window as any).Capacitor.isNativePlatform?.() === true;
  }

  // ─── Position timer: update seekbar in notification every second ──────────
  private startPositionTimer() {
    this.stopPositionTimer();
    this.positionTimer = setInterval(() => this.syncPositionState(), 1000);
  }

  private stopPositionTimer() {
    if (this.positionTimer) {
      clearInterval(this.positionTimer);
      this.positionTimer = null;
    }
  }

  // ─── Media Session helpers ─────────────────────────────────────────────────

  private async updateMediaSession(song: LocalSong) {
    if (this.isNative()) {
      // Native Android: use Capacitor plugin
      const plugin = await getMediaSessionPlugin();
      if (!plugin) return;

      try {
        await plugin.setMetadata({
          artist: song.artist || 'Unknown Artist',
          title: song.title || 'Unknown Title',
          album: song.album || 'KyokoBeat',
          artwork: song.cover ? [{ src: song.cover, sizes: '512x512', type: 'image/jpeg' }] : [],
        });

        // Register action handlers via plugin
        await plugin.setActionHandler({ action: 'play' }, async () => {
          await this.audio.play();
          this.syncPlaybackState('playing');
        });
        await plugin.setActionHandler({ action: 'pause' }, () => {
          this.audio.pause();
          this.syncPlaybackState('paused');
        });
        await plugin.setActionHandler({ action: 'previoustrack' }, () => {
          if (this.onPrevTrack) this.onPrevTrack();
        });
        await plugin.setActionHandler({ action: 'nexttrack' }, () => {
          if (this.onTrackEnded) this.onTrackEnded();
        });
        await plugin.setActionHandler({ action: 'seekto' }, (details: any) => {
          if (details?.seekTime !== undefined) {
            this.audio.currentTime = details.seekTime;
          }
        });
      } catch (e) {
        console.warn('MediaSession plugin error:', e);
      }
    } else {
      // Web browser: use standard Media Session API
      if (!('mediaSession' in navigator)) return;

      navigator.mediaSession.metadata = new MediaMetadata({
        title: song.title || 'Unknown Title',
        artist: song.artist || 'Unknown Artist',
        album: song.album || 'KyokoBeat',
        artwork: song.cover ? [{ src: song.cover, sizes: '512x512', type: 'image/jpeg' }] : [],
      });

      navigator.mediaSession.setActionHandler('play', () => { this.audio.play().catch(() => {}); });
      navigator.mediaSession.setActionHandler('pause', () => { this.audio.pause(); });
      navigator.mediaSession.setActionHandler('previoustrack', () => { if (this.onPrevTrack) this.onPrevTrack(); });
      navigator.mediaSession.setActionHandler('nexttrack', () => { if (this.onTrackEnded) this.onTrackEnded(); });
      navigator.mediaSession.setActionHandler('seekto', (d) => {
        if (d.seekTime !== undefined) this.audio.currentTime = d.seekTime;
      });
      navigator.mediaSession.setActionHandler('seekbackward', (d) => {
        this.audio.currentTime = Math.max(0, this.audio.currentTime - (d.seekOffset ?? 10));
      });
      navigator.mediaSession.setActionHandler('seekforward', (d) => {
        this.audio.currentTime = Math.min(this.audio.duration || 0, this.audio.currentTime + (d.seekOffset ?? 10));
      });
    }
  }

  private async syncPlaybackState(state: 'playing' | 'paused' | 'stopped' | 'none') {
    if (this.isNative()) {
      const plugin = await getMediaSessionPlugin();
      if (!plugin) return;
      try {
        await plugin.setPlaybackState({ playbackState: state });
      } catch (e) { /* ignore */ }
    } else {
      if (!('mediaSession' in navigator)) return;
      navigator.mediaSession.playbackState = state === 'playing' ? 'playing' : 'paused';
    }
  }

  private async syncPositionState() {
    if (!this.audio.duration || isNaN(this.audio.duration)) return;

    if (this.isNative()) {
      const plugin = await getMediaSessionPlugin();
      if (!plugin) return;
      try {
        await plugin.setPositionState({
          duration: this.audio.duration,
          playbackRate: this.audio.playbackRate,
          position: this.audio.currentTime,
        });
      } catch (e) { /* ignore */ }
    } else {
      if (!('mediaSession' in navigator)) return;
      try {
        navigator.mediaSession.setPositionState({
          duration: this.audio.duration,
          playbackRate: this.audio.playbackRate,
          position: this.audio.currentTime,
        });
      } catch (_) { /* not supported on all browsers */ }
    }
  }

  // ─── Web Audio API ─────────────────────────────────────────────────────────

  private initAudioContext() {
    if (this.audioContext) return;
    if (this.isNative()) return;

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

  private async ensureAudioContextRunning() {
    if (!this.audioContext) return;
    try {
      if (this.audioContext.state === 'suspended') await this.audioContext.resume();
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

  // ─── Public API ───────────────────────────────────────────────────────────

  public subscribe(callback: AudioStateCallback) {
    this.callbacks.add(callback);
    this.notifyState();
    return () => { this.callbacks.delete(callback); };
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

    if (!native) {
      this.initAudioContext();
      await this.ensureAudioContextRunning();
    }

    try {
      let src = '';

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
        await this.updateMediaSession(song);
        this.notifyState();
        return;
      }

      // === WEB BROWSER PATH ===
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
        if (this.lastCrossOrigin) { this.audio.removeAttribute('crossorigin'); this.lastCrossOrigin = false; }
        src = song.audioUrl;
      } else {
        if (this.lastCrossOrigin) { this.audio.removeAttribute('crossorigin'); this.lastCrossOrigin = false; }
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

      await this.updateMediaSession(song);
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

  public getCurrentSong() { return this.currentSong; }
  public isPlaying() { return !this.audio.paused && !this.audio.ended; }
}

export const audioManager = new AudioManager();
export default audioManager;
