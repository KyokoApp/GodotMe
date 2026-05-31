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

  constructor() {
    this.audio = new Audio();
    
    // Set up standard audio events
    this.audio.addEventListener('play', () => this.notifyState());
    this.audio.addEventListener('pause', () => this.notifyState());
    this.audio.addEventListener('timeupdate', () => this.notifyState());
    this.audio.addEventListener('durationchange', () => this.notifyState());
    this.audio.addEventListener('volumechange', () => this.notifyState());
    this.audio.addEventListener('ended', () => {
      this.notifyState();
      this.handleTrackEnded();
    });
  }

  // Set callback for track ended (so player can play next)
  public onTrackEnded: (() => void) | null = null;

  private handleTrackEnded() {
    if (this.onTrackEnded) {
      this.onTrackEnded();
    }
  }

  // Lazily initialize Web Audio API to satisfy browser gesture requirements
  private initAudioContext() {
    if (this.audioContext) return;

    try {
      this.audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
      this.analyser = this.audioContext.createAnalyser();
      this.analyser.fftSize = 256; // High resolution but performant for visualizer

      // Connect HTMLAudioElement to Web Audio graph
      this.sourceNode = this.audioContext.createMediaElementSource(this.audio);
      this.sourceNode.connect(this.analyser);
      this.analyser.connect(this.audioContext.destination);
    } catch (e) {
      console.warn('Web Audio API not fully supported or blocked:', e);
    }
  }

  public subscribe(callback: AudioStateCallback) {
    this.callbacks.add(callback);
    // Initial notification
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
    if (this.audioContext && this.audioContext.state === 'suspended') {
      await this.audioContext.resume();
    }

    try {
      let src = '';
      if (song.isCloud && song.audioUrl) {
        src = song.audioUrl;
        this.audio.crossOrigin = 'anonymous';
      } else if (song.audioUrl) {
        // Mobile Capacitor converted file src
        src = song.audioUrl;
        this.audio.removeAttribute('crossorigin');
      } else {
        // Local web file
        this.audio.removeAttribute('crossorigin');
        const file = await song.fileHandle.getFile();
        src = URL.createObjectURL(file);
      }

      // Revoke old object URL if any (to prevent memory leaks)
      if (this.audio.src && this.audio.src.startsWith('blob:')) {
        URL.revokeObjectURL(this.audio.src);
      }

      this.currentSong = song;
      this.audio.src = src;

      try {
        await this.audio.play();
      } catch (playError: any) {
        if (song.isCloud) {
          console.warn("Play with CORS failed, retrying without CORS...", playError);
          this.audio.removeAttribute('crossorigin');
          this.audio.src = src; // reload source without crossorigin
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
    if (this.audioContext && this.audioContext.state === 'suspended') {
      await this.audioContext.resume();
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
    // Clamp between 0 and 1
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
