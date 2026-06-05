import { registerPlugin } from '@capacitor/core';

export interface WAStickerPlugin {
  /**
   * Kirim .wastickers ZIP (base64) → WA buka "Tambahkan ke stiker Anda"
   */
  openPack(options: {
    data: string;     // base64 dari file .wastickers (ZIP)
    packName: string; // nama pack, dipakai sebagai nama file
  }): Promise<{ success: boolean }>;
}

const WASticker = registerPlugin<WAStickerPlugin>('WASticker');
export { WASticker };
