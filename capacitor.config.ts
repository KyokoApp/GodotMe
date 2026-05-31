import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.kyokobeat.musicplayer',
  appName: 'KyokoBeat',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
    hostname: 'kyokobeat.app',
    cleartext: true
  },
  android: {
    allowMixedContent: true,
    webContentsDebuggingEnabled: true
  }
};

export default config;
