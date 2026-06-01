import { LocalSong } from './db';

type AudioStateCallback = (state: {
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  currentSong: LocalSong | null;
  isMuted: boolean;
}) => void;

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
    
    this.audio.addEventListener('play', () => this.notifyState());
    this.audio.addEventListener('pause', () => this.notifyState());
    this.audio.addEventListener('timeupdate', () => this.notifyState());
    this.audio.addEventListener('durationchange', () => this.notifyState());
    this.audio.addEventListener('volumechange', () => this.notifyState());
    this.audio.addEventListener('ended', () => {
      this.notifyState();
      this.handleTrackEnded();
    });
    this.audio.addEventListener('error', (e) => {
      console.error('Audio element error:', this.audio.error);
    });
  }

  public onTrackEnded: (() => void) | null = null;

  private handleTrackEnded() {
    if (this.onTrackEnded) {
      this.onTrackEnded();
    }
  }

  // Lazily initialize Web Audio API
  private initAudioContext() {
    if (this.audioContext) return;

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
        // Recreate if closed
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
    this.initAudioContext();
    await this.ensureAudioContextRunning();

    try {
      let src = '';
      const needsCors = !!(song.isCloud || song.isDownloaded) && !!(song.audioUrl);

      if (song.isCloud && song.audioUrl) {
        // Cloud streaming — needs CORS for Web Audio API
        src = song.audioUrl;
        this.audio.crossOrigin = 'anonymous';
        this.lastCrossOrigin = true;
      } else if (song.isDownloaded && song.audioUrl) {
        // Downloaded from cloud (web fallback using Cloudinary URL) — also needs CORS
        src = song.audioUrl;
        this.audio.crossOrigin = 'anonymous';
        this.lastCrossOrigin = true;
      } else if (song.audioUrl) {
        // Mobile Capacitor native file (capacitor:// or content://)
        // Remove crossorigin ONLY if previous song had it (reset properly)
        if (this.lastCrossOrigin) {
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
        }
        src = song.audioUrl;
      } else {
        // Local web file via FileHandle (blob URL)
        if (this.lastCrossOrigin) {
          this.audio.removeAttribute('crossorigin');
          this.lastCrossOrigin = false;
        }
        const file = await song.fileHandle.getFile();
        src = URL.createObjectURL(file);
      }

      // Revoke old object URL
      if (this.audio.src && this.audio.src.startsWith('blob:')) {
        URL.revokeObjectURL(this.audio.src);
      }

      this.currentSong = song;

      // Important: set src AFTER setting crossOrigin attribute
      this.audio.src = src;
      this.audio.load(); // Force reload to apply crossOrigin change

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

      this.notifyState();
    } catch (error) {
      console.error('Failed to play song:', error);
      throw error;
    }
  }

  public async togglePlay() {
    if (!this.currentSong) return;
    
    this.initAudioContext();
    await this.ensureAudioContextRunning();

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

  public getCurrentSong() {
    return this.currentSong;
  }

  public isPlaying() {
    return !this.audio.paused && !this.audio.ended;
  }
}

export const audioManager = new AudioManager();
export default audioManager;
