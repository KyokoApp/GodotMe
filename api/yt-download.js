// YouTube Audio Downloader API
// Proxy dengan fallback otomatis ke beberapa API
// Ganti/tambah API di array APIS tanpa perlu update APK

const APIS = [
  {
    name: 'api-faa',
    buildUrl: (url) => `https://api-faa.my.id/faa/ytmp3?url=${encodeURIComponent(url)}`,
    extract: (data) => ({
      audioUrl: data?.result?.mp3 || data?.result?.url || data?.result?.audio || null,
      title: data?.result?.title || null,
      thumbnail: data?.result?.thumbnail || null,
      duration: data?.result?.duration || 0,
    }),
  },
  {
    name: 'nexray',
    buildUrl: (url) => `https://api.nexray.web.id/download/ytmp3?url=${encodeURIComponent(url)}`,
    extract: (data) => ({
      audioUrl: data?.data?.audio || data?.data?.url || data?.result?.url || null,
      title: data?.data?.title || data?.result?.title || null,
      thumbnail: data?.data?.thumbnail || null,
      duration: data?.data?.duration || 0,
    }),
  },
  {
    name: 'itzpire',
    buildUrl: (url) => `https://itzpire.com/download/ytmp3?url=${encodeURIComponent(url)}`,
    extract: (data) => ({
      audioUrl: data?.data?.audio?.url || data?.data?.url || null,
      title: data?.data?.title || null,
      thumbnail: data?.data?.thumbnail || null,
      duration: data?.data?.duration || 0,
    }),
  },
];

// Validasi URL YouTube
function isYouTubeUrl(url) {
  return /^https?:\/\/(www\.)?(youtube\.com\/(watch\?v=|shorts\/|music)|youtu\.be\/)/.test(url);
}

// Ekstrak YouTube ID
function getYouTubeId(url) {
  const match = url.match(/(?:youtube\.com\/(?:watch\?v=|shorts\/)|youtu\.be\/|music\.youtube\.com\/watch\?v=)([a-zA-Z0-9_-]{11})/);
  return match?.[1] || null;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'GET' && req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const url = req.query?.url || req.body?.url;

  if (!url) {
    return res.status(400).json({ error: 'Parameter url diperlukan' });
  }

  if (!isYouTubeUrl(url)) {
    return res.status(400).json({ error: 'URL bukan link YouTube yang valid' });
  }

  const ytId = getYouTubeId(url);
  const fallbackThumbnail = ytId ? `https://i.ytimg.com/vi/${ytId}/hqdefault.jpg` : null;

  let lastError = null;

  // Coba satu per satu API, pakai yang pertama berhasil
  for (const api of APIS) {
    try {
      console.log(`[yt-download] Mencoba API: ${api.name}`);

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 20000); // 20s timeout per API

      const response = await fetch(api.buildUrl(url), {
        signal: controller.signal,
        headers: { 'User-Agent': 'Mozilla/5.0' },
      });
      clearTimeout(timeout);

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const data = await response.json();
      const extracted = api.extract(data);

      if (!extracted.audioUrl) {
        throw new Error('Audio URL tidak ditemukan di response');
      }

      console.log(`[yt-download] Berhasil via ${api.name}: ${extracted.title}`);

      return res.status(200).json({
        success: true,
        api: api.name,
        audioUrl: extracted.audioUrl,
        title: extracted.title || 'Unknown Title',
        thumbnail: extracted.thumbnail || fallbackThumbnail,
        duration: extracted.duration || 0,
      });

    } catch (e) {
      console.warn(`[yt-download] API ${api.name} gagal:`, e.message);
      lastError = e;
      // Lanjut ke API berikutnya
    }
  }

  // Semua API gagal
  console.error('[yt-download] Semua API gagal:', lastError?.message);
  return res.status(502).json({
    error: 'Semua API sedang tidak tersedia. Coba lagi nanti.',
    detail: lastError?.message,
  });
}
