import { Filesystem, Directory } from '@capacitor/filesystem';

// URL file version.json di GitHub Releases
const VERSION_URL =
  'https://github.com/KyokoApp/KyokoBeat/releases/latest/download/version.json';

// Versi app saat ini — otomatis dari package.json via Vite
export const CURRENT_VERSION: string =
  (import.meta as any).env?.VITE_APP_VERSION || '1.0.0';

export interface UpdateInfo {
  version: string;
  apkUrl: string;
  changelog: string;
}

/** Cek apakah ada versi baru. Return null kalau gagal / sudah up to date. */
export async function checkForUpdate(): Promise<UpdateInfo | null> {
  try {
    const res = await fetch(VERSION_URL + '?t=' + Date.now());
    if (!res.ok) return null;
    const data: UpdateInfo = await res.json();
    if (compareVersions(data.version, CURRENT_VERSION) > 0) {
      return data;
    }
    return null;
  } catch {
    return null;
  }
}

/** Download APK ke storage internal lalu trigger install */
export async function downloadAndInstall(
  apkUrl: string,
  onProgress: (pct: number) => void
): Promise<void> {
  // Download via fetch + stream progress
  const res = await fetch(apkUrl);
  if (!res.ok) throw new Error('Gagal download APK');

  const contentLength = Number(res.headers.get('content-length') || 0);
  const reader = res.body!.getReader();
  const chunks: Uint8Array[] = [];
  let received = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.length;
    if (contentLength > 0) onProgress(Math.round((received / contentLength) * 100));
  }

  // Gabung semua chunk jadi base64
  const blob = new Blob(chunks as BlobPart[], { type: 'application/vnd.android.package-archive' });
  const base64 = await blobToBase64(blob);

  // Simpan ke Downloads
  await Filesystem.writeFile({
    path: 'KyokoBeat-update.apk',
    data: base64,
    directory: Directory.External,
  });

  // Trigger install via Android Intent
  const getUriResult = await Filesystem.getUri({
    path: 'KyokoBeat-update.apk',
    directory: Directory.External,
  });

  const fileUri = getUriResult.uri;

  // Pakai Capacitor Browser / window open untuk trigger install
  (window as any).AndroidInstallApk?.install(fileUri);

  // Fallback: buka file manager ke path apk
  if (!(window as any).AndroidInstallApk) {
    window.open(fileUri, '_system');
  }
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve(result.split(',')[1]);
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

/** Bandingkan versi semver. Return > 0 kalau a lebih baru dari b */
function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0);
    if (diff !== 0) return diff;
  }
  return 0;
}
