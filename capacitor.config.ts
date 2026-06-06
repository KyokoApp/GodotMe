import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.kyokobeat.musicplayer',
  appName: 'KyokoBeat',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
    cleartext: true
  },
  android: {
    allowMixedContent: true,
    backgroundColor: '#0a0a0a',
    webContentsDebuggingEnabled: false,
  },
  plugins: {
    SplashScreen: {
      backgroundColor: '#0a0a0a',
      showSpinner: false,
      launchAutoHide: true,
      launchShowDuration: 0,
    },
    // @jofr/capacitor-media-session — enables Android media notification with
    // play/pause/next/prev controls on the lock screen & notification shade
    MediaSession: {
      // No extra config needed; the plugin picks up Android foreground service automatically
    },
  },
};

export default config;
