import { registerPlugin } from '@capacitor/core';

export interface StickerItem {
  fileName: string; // e.g. "1.webp"
  data: string;     // base64 WebP 512x512
  emoji: string;    // e.g. "😊"
}

export interface WAStickerPlugin {
  /**
   * Simpan stiker ke cache lalu fire ENABLE_STICKER_PACK intent.
   * WhatsApp langsung tampilkan sheet "Tambahkan ke stiker Anda".
   */
  openPack(options: {
    packId: string;
    packName: string;
    publisher: string;
    trayData: string;   // base64 WebP 96x96
    stickers: StickerItem[];
  }): Promise<{ success: boolean }>;
}

const WASticker = registerPlugin<WAStickerPlugin>('WASticker');
export { WASticker };
