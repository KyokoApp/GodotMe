import { registerPlugin } from '@capacitor/core';

interface FloatingLyricsPlugin {
  requestPermission(): Promise<{ granted: boolean; prompted?: boolean }>;
  checkPermission(): Promise<{ granted: boolean }>;
  showLyrics(options: { line: string }): Promise<{ ok: boolean }>;
  hideLyrics(): Promise<{ ok: boolean }>;
  isVisible(): Promise<{ visible: boolean }>;
}

const FloatingLyrics = registerPlugin<FloatingLyricsPlugin>('FloatingLyrics');

export async function checkFloatingPermission(): Promise<boolean> {
  try {
    const { granted } = await FloatingLyrics.checkPermission();
    return granted;
  } catch {
    return false;
  }
}

export async function requestFloatingPermission(): Promise<boolean> {
  try {
    const result = await FloatingLyrics.requestPermission();
    return result.granted;
  } catch {
    return false;
  }
}

export async function showFloatingLyric(line: string): Promise<void> {
  try {
    await FloatingLyrics.showLyrics({ line: line || '♪' });
  } catch {
    // not on native, silently ignore
  }
}

export async function hideFloatingLyric(): Promise<void> {
  try {
    await FloatingLyrics.hideLyrics();
  } catch {}
}

export async function isFloatingVisible(): Promise<boolean> {
  try {
    const { visible } = await FloatingLyrics.isVisible();
    return visible;
  } catch {
    return false;
  }
}
