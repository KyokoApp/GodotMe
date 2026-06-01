// YouTube Audio Downloader API
// Primary: @distube/ytdl-core (direct, no binary needed)
// Fallback: External APIs

import ytdl from '@distube/ytdl-core';

const FALLBACK_APIS = [
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
      audioUrl: data?.data?.audio || data?.data?.url || null,
      title: data?.data?.title || null,
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

function isYouTubeUrl(url) {
  return /^https?:\/\/(www\.)?(youtube\.com\/(watch\?v=|shorts\/|music)|youtu\.be\/)/.test(url);
}

function getYouTubeId(url) {
  const match = url.match(/(?:youtube\.com\/(?:watch\?v=|shorts\/)|youtu\.be\/|music\.youtube\.com\/watch\?v=)([a-zA-Z0-9_-]{11})/);
  return match?.[1] || null;
}

// Primary: ambil audio URL langsung via ytdl-core
async function tryYtdlCore(url) {
  const info = await ytdl.getInfo(url);
  const title = info.videoDetails.title;
  const thumbnail = info.videoDetails.thumbnails?.slice(-1)[0]?.url || null;
  const durationSec = parseInt(info.videoDetails.lengthSeconds) || 0;

  // Pilih format audio terbaik (mp4a/webm, no video)
  const format = ytdl.chooseFormat(info.formats, {
    quality: 'highestaudio',
    filter: 'audioonly',
  });

  if (!format?.url) throw new Error('Tidak ada format audio tersedia');

  return {
    audioUrl: format.url,
    title,
    thumbnail,
    duration: durationSec,
  };
}

// Fallback: coba external API satu per satu
async function tryFallbackApis(url, fallbackThumbnail) {
  let lastError = null;

  for (const api of FALLBACK_APIS) {
    try {
      console.log(`[yt-download] Fallback ke API: ${api.name}`);

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 20000);

      const response = await fetch(api.buildUrl(url), {
        signal: controller.signal,
        headers: { 'User-Agent': 'Mozilla/5.0' },
      });
      clearTimeout(timeout);

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      const extracted = api.extract(data);

      if (!extracted.audioUrl) throw new Error('Audio URL tidak ditemukan');

      console.log(`[yt-download] Berhasil via ${api.name}`);
      return { ...extracted, thumbnail: extracted.thumbnail || fallbackThumbnail, api: api.name };

    } catch (e) {
      console.warn(`[yt-download] ${api.name} gagal:`, e.message);
      lastError = e;
    }
  }

  throw lastError || new Error('Semua API gagal');
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

  if (!url) return res.status(400).json({ error: 'Parameter url diperlukan' });
  if (!isYouTubeUrl(url)) return res.status(400).json({ error: 'URL bukan link YouTube yang valid' });

  const ytId = getYouTubeId(url);
  const fallbackThumbnail = ytId ? `https://i.ytimg.com/vi/${ytId}/hqdefault.jpg` : null;

  // Coba ytdl-core dulu
  try {
    console.log('[yt-download] Mencoba ytdl-core...');
    const result = await tryYtdlCore(url);
    console.log(`[yt-download] Berhasil via ytdl-core: ${result.title}`);
    return res.status(200).json({
      success: true,
      api: 'ytdl-core',
      audioUrl: result.audioUrl,
      title: result.title,
      thumbnail: result.thumbnail || fallbackThumbnail,
      duration: result.duration,
    });
  } catch (e) {
    console.warn('[yt-download] ytdl-core gagal:', e.message);
  }

  // Kalau ytdl-core gagal, coba external API
  try {
    const result = await tryFallbackApis(url, fallbackThumbnail);
    return res.status(200).json({
      success: true,
      api: result.api,
      audioUrl: result.audioUrl,
      title: result.title || 'Unknown Title',
      thumbnail: result.thumbnail,
      duration: result.duration || 0,
    });
  } catch (e) {
    console.error('[yt-download] Semua metode gagal:', e.message);
    return res.status(502).json({
      error: 'Semua metode download sedang tidak tersedia. Coba lagi nanti.',
      detail: e.message,
    });
  }
}
