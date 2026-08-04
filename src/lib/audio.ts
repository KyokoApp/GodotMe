import { LocalSong } from './db';

type AudioStateCallback = (state: {
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  currentSong: LocalSong | null;
  isMuted: boolean;
}) => void;

// ─── @jofr/capacitor-media-session lazy loader ────────────────────────────
// API mirip Web Media Session tapi harus pakai plugin di native Android
let _mediaPlugin: any = null;
async function getPlugin() {
  if (_mediaPlugin) return _mediaPlugin;
  try {
    const mod = await import('@jofr/capacitor-media-session');
    _mediaPlugin = mod.MediaSession;
    return _mediaPlugin;
  } catch {
    return null;
  }
}

class AudioManager {
  private audio: HTMLAudioElement;
  private audioContext: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private sourceNode: MediaElementAudioSourceNode | null = null;
  private currentSong: LocalSong | null = null;
  private callbacks: Set<AudioStateCallback> = new Set();
  private lastCrossOrigin = false;
  private positionTimer: ReturnType<typeof setInterval> | null = null;
  private handlersRegistered = false;

  constructor() {
    this.audio = new Audio();
    this.audio.preload = 'auto';

    this.audio.addEventListener('play', () => {
      this.notifyState();
      this.setPlaybackState('playing');
      this.startPositionTimer();
    });
    this.audio.addEventListener('pause', () => {
      this.notifyState();
      this.setPlaybackState('paused');
      this.stopPositionTimer();
    });
    this.audio.addEventListener('timeupdate', () => this.notifyState());
    this.audio.addEventListener('durationchange', () => this.notifyState());
    this.audio.addEventListener('volumechange', () => this.notifyState());
    this.audio.addEventListener('ended', () => {
      this.notifyState();
      this.setPlaybackState('paused'); // keep notification visible while transitioning to next track
      this.stopPositionTimer();
      if (this.onTrackEnded) this.onTrackEnded();
    });
  }

  public onTrackEnded: (() => void) | null = null;
  public onPrevTrack: (() => void) | null = null;

  // ─── native check ──────────────────────────────────────────────────────────
  private isNative(): boolean {
    return typeof window !== 'undefined' &&
      !!(window as any).Capacitor?.isNativePlatform?.();
  }

  // ─── position sync timer ───────────────────────────────────────────────────
  private startPositionTimer() {
    this.stopPositionTimer();
    this.positionTimer = setInterval(() => this.syncPosition(), 1000);
  }

  private stopPositionTimer() {
    if (this.positionTimer) { clearInterval(this.positionTimer); this.positionTimer = null; }
  }

  // ─── Media Session ─────────────────────────────────────────────────────────

  // Register action handlers ONCE — important, jofr plugin caches these
  private async registerHandlers() {
    if (this.handlersRegistered) return;
    this.handlersRegistered = true;

    if (this.isNative()) {
      const plugin = await getPlugin();
      if (!plugin) return;
      try {
        await plugin.setActionHandler({ action: 'play' }, async () => {
          await this.audio.play().catch(() => {});
          this.setPlaybackState('playing');
        });
        await plugin.setActionHandler({ action: 'pause' }, () => {
          this.audio.pause();
          this.setPlaybackState('paused');
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
            this.syncPosition();
          }
        });
        await plugin.setActionHandler({ action: 'seekbackward' }, (details: any) => {
          this.audio.currentTime = Math.max(0, this.audio.currentTime - (details?.seekOffset ?? 10));
          this.syncPosition();
        });
        await plugin.setActionHandler({ action: 'seekforward' }, (details: any) => {
          this.audio.currentTime = Math.min(this.audio.duration || 0, this.audio.currentTime + (details?.seekOffset ?? 10));
          this.syncPosition();
        });
      } catch (e) {
        console.warn('[MediaSession] registerHandlers error:', e);
      }
    } else {
      if (!('mediaSession' in navigator)) return;
      navigator.mediaSession.setActionHandler('play', () => { this.audio.play().catch(() => {}); });
      navigator.mediaSession.setActionHandler('pause', () => { this.audio.pause(); });
      navigator.mediaSession.setActionHandler('previoustrack', () => { if (this.onPrevTrack) this.onPrevTrack(); });
      navigator.mediaSession.setActionHandler('nexttrack', () => { if (this.onTrackEnded) this.onTrackEnded(); });
      navigator.mediaSession.setActionHandler('seekto', (d) => { if (d.seekTime !== undefined) this.audio.currentTime = d.seekTime; });
      navigator.mediaSession.setActionHandler('seekbackward', (d) => { this.audio.currentTime = Math.max(0, this.audio.currentTime - (d.seekOffset ?? 10)); });
      navigator.mediaSession.setActionHandler('seekforward', (d) => { this.audio.currentTime = Math.min(this.audio.duration || 0, this.audio.currentTime + (d.seekOffset ?? 10)); });
    }
  }

  private async updateMetadata(song: LocalSong) {
    const meta = {
      title: song.title || 'Unknown Title',
      artist: song.artist || 'Unknown Artist',
      album: song.album || 'KyokoBeat',
      artwork: song.cover ? [{ src: song.cover, sizes: '512x512', type: 'image/jpeg' }] : [],
    };

    if (this.isNative()) {
      const plugin = await getPlugin();
      if (!plugin) return;
      try {
        await plugin.setMetadata(meta);
      } catch (e) {
        console.warn('[MediaSession] setMetadata error:', e);
      }
    } else {
      if (!('mediaSession' in navigator)) return;
      navigator.mediaSession.metadata = new MediaMetadata(meta);
    }
  }

  private async setPlaybackState(state: 'playing' | 'paused' | 'none') {
    if (this.isNative()) {
      const plugin = await getPlugin();
      if (!plugin) return;
      try {
        // CRITICAL: must call setPlaybackState('playing') for notification to appear
        await plugin.setPlaybackState({ playbackState: state });
      } catch (e) {
        console.warn('[MediaSession] setPlaybackState error:', e);
      }
    } else {
      if (!('mediaSession' in navigator)) return;
      navigator.mediaSession.playbackState = state === 'playing' ? 'playing' : 'paused';
    }
  }

  private async syncPosition() {
    if (!this.audio.duration || isNaN(this.audio.duration)) return;
    const posState = {
      duration: this.audio.duration,
      playbackRate: this.audio.playbackRate,
      position: this.audio.currentTime,
    };

    if (this.isNative()) {
      const plugin = await getPlugin();
      if (!plugin) return;
      try { await plugin.setPositionState(posState); } catch (_) {}
    } else {
      if (!('mediaSession' in navigator)) return;
      try { navigator.mediaSession.setPositionState(posState); } catch (_) {}
    }
  }

  // ─── Web Audio API (web/browser only) ────────────────────────────────────
  private initAudioContext() {
    if (this.audioContext || this.isNative()) return;
    try {
      this.audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
      this.analyser = this.audioContext.createAnalyser();
      this.analyser.fftSize = 256;
      this.sourceNode = this.audioContext.createMediaElementSource(this.audio);
      this.sourceNode.connect(this.analyser);
      this.analyser.connect(this.audioContext.destination);
    } catch (e) { console.warn('Web Audio API error:', e); }
  }

  private async ensureAudioContextRunning() {
    if (!this.audioContext) return;
    try {
      if (this.audioContext.state === 'suspended') await this.audioContext.resume();
    } catch (e) { console.warn('AudioContext resume error:', e); }
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

    // Register handlers once before first play
    await this.registerHandlers();

    try {
      let src = '';

      if (native) {
        if (this.lastCrossOrigin) { this.audio.removeAttribute('crossorigin'); this.lastCrossOrigin = false; }

        if (song.audioUrl) {
          src = song.audioUrl;
          // If it's a raw device path (not yet converted), convert it
          if (src.startsWith('/storage/') || src.startsWith('/data/') || src.startsWith('/sdcard/')) {
            try {
              const { Capacitor } = await import('@capacitor/core');
              src = Capacitor.convertFileSrc(song.audioUrl);
            } catch (e) { console.warn('convertFileSrc error:', e); }
          }
        } else if (song.path) {
          // Fallback: convert path directly
          try {
            const { Capacitor } = await import('@capacitor/core');
            src = Capacitor.convertFileSrc(song.path);
          } catch (e) { console.warn('convertFileSrc path error:', e); }
        } else if (song.fileHandle) {
          // Only use fileHandle if it's actually available (not null)
          try {
            const file = await song.fileHandle.getFile();
            src = URL.createObjectURL(file);
          } catch (e) { console.warn('fileHandle.getFile error:', e); }
        }

        if (!src) throw new Error('Tidak ada sumber audio yang valid untuk lagu ini');

        if (this.audio.src?.startsWith('blob:')) URL.revokeObjectURL(this.audio.src);

        this.currentSong = song;
        this.audio.src = src;
        this.audio.load();
        await this.audio.play();

        // Update metadata THEN set state to 'playing' — ORDER MATTERS for notification.
        // setPlaybackState('playing') is what makes @jofr/capacitor-media-session start its
        // own foreground service — this alone covers both background keepalive AND the
        // lockscreen/notification controls, no separate native service needed.
        await this.updateMetadata(song);
        await this.setPlaybackState('playing');
        this.notifyState();
        return;
      }

      // === WEB PATH ===
      const needsCors = !!(song.isCloud || song.isDownloaded) && !!song.audioUrl;

      if ((song.isCloud || song.isDownloaded) && song.audioUrl) {
        src = song.audioUrl;
        this.audio.crossOrigin = 'anonymous';
        this.lastCrossOrigin = true;
      } else if (song.audioUrl) {
        if (this.lastCrossOrigin) { this.audio.removeAttribute('crossorigin'); this.lastCrossOrigin = false; }
        src = song.audioUrl;
      } else if (song.fileHandle) {
        if (this.lastCrossOrigin) { this.audio.removeAttribute('crossorigin'); this.lastCrossOrigin = false; }
        const file = await song.fileHandle.getFile();
        src = URL.createObjectURL(file);
      } else {
        throw new Error('Tidak ada sumber audio yang valid');
      }

      if (this.audio.src?.startsWith('blob:')) URL.revokeObjectURL(this.audio.src);

      this.currentSong = song;
      this.audio.src = src;
      this.audio.load();

      try {
        await this.audio.play();
      } catch (playError: any) {
        if (needsCors) {
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
          this.audio.src = src;
          this.audio.load();
          await this.audio.play();
        } else {
          throw playError;
        }
      }

      await this.updateMetadata(song);
      await this.setPlaybackState('playing');
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
    this.syncPosition();
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
      const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
      this.analyser.getByteFrequencyData(dataArray);
      return dataArray;
    } catch { return null; }
  }

  public getCurrentSong() { return this.currentSong; }
  public isPlaying() { return !this.audio.paused && !this.audio.ended; }
}

export const audioManager = new AudioManager();
export default audioManager;
