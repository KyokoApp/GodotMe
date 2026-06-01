import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.kyokobeat.musicplayer',
  appName: 'KyokoBeat',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
    url: 'https://kyoko-beat.vercel.app',
    cleartext: true
  },
  android: {
    allowMixedContent: true
  }
};

export default config;
