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
  },
};

export default config;
