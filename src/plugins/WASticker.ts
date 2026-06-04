import { registerPlugin } from '@capacitor/core';

export interface WAStickerPlugin {
  openPack(options: { data: string; packName: string }): Promise<{ success: boolean }>;
}

// Nama harus sama persis dengan @CapacitorPlugin(name = "WASticker") di Java
const WASticker = registerPlugin<WAStickerPlugin>('WASticker');

export { WASticker };
