// YouTube Audio Downloader API
// Prioritas: RapidAPI → Cobalt → fallback lainnya

const APIS = [
  // PRIORITAS 1: RapidAPI - paling stabil dari Vercel
  {
    name: 'rapidapi-ytmp3',
    buildUrl: (url) => `https://youtube-mp36.p.rapidapi.com/dl?id=${extractYtId(url)}`,
    method: 'GET',
    buildBody: () => null,
    buildHeaders: () => ({
      'X-RapidAPI-Key': process.env.RAPIDAPI_KEY || '',
      'X-RapidAPI-Host': 'youtube-mp36.p.rapidapi.com',
    }),
    extract: (data) => ({
      audioUrl: data?.link || null,
      title: data?.title || null,
      thumbnail: null,
      duration: data?.duration || 0,
    }),
    requiresEnv: 'RAPIDAPI_KEY',
  },
  // PRIORITAS 2: Cobalt - open source, server-friendly
  {
    name: 'cobalt',
    buildUrl: () => `https://co.wuk.sh/api/json`,
    method: 'POST',
    buildBody: (url) => JSON.stringify({ url, isAudioOnly: true, aFormat: 'mp3', filenamePattern: 'pretty' }),
    buildHeaders: () => ({ 'Accept': 'application/json', 'Content-Type': 'application/json' }),
    extract: (data) => ({
      audioUrl: data?.url || null,
      title: data?.filename?.replace(/\.mp3$/i, '') || null,
      thumbnail: null,
      duration: 0,
    }),
  },
  // FALLBACK: api-faa
  {
    name: 'api-faa',
    buildUrl: (url) => `https://api-faa.my.id/faa/ytmp3?url=${encodeURIComponent(url)}`,
    method: 'GET',
    buildBody: () => null,
    buildHeaders: () => ({ 'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' }),
    extract: (data) => ({
      audioUrl: data?.result?.mp3 || data?.result?.url || data?.result?.audio || null,
      title: data?.result?.title || null,
      thumbnail: data?.result?.thumbnail || null,
      duration: data?.result?.duration || 0,
    }),
  },
  // FALLBACK: nexray
  {
    name: 'nexray',
    buildUrl: (url) => `https://api.nexray.web.id/download/ytmp3?url=${encodeURIComponent(url)}`,
    method: 'GET',
    buildBody: () => null,
    buildHeaders: () => ({ 'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' }),
    extract: (data) => ({
      audioUrl: data?.data?.audio || data?.data?.url || data?.result?.url || null,
      title: data?.data?.title || data?.result?.title || null,
      thumbnail: data?.data?.thumbnail || null,
      duration: data?.data?.duration || 0,
    }),
  },
  // FALLBACK: itzpire
  {
    name: 'itzpire',
    buildUrl: (url) => `https://itzpire.com/download/ytmp3?url=${encodeURIComponent(url)}`,
    method: 'GET',
    buildBody: () => null,
    buildHeaders: () => ({ 'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' }),
    extract: (data) => ({
      audioUrl: data?.data?.audio?.url || data?.data?.url || null,
      title: data?.data?.title || null,
      thumbnail: data?.data?.thumbnail || null,
      duration: data?.data?.duration || 0,
    }),
  },
];

function extractYtId(url) {
  const match = url?.match(/(?:youtube\.com\/(?:watch\?v=|shorts\/)|youtu\.be\/|music\.youtube\.com\/watch\?v=)([a-zA-Z0-9_-]{11})/);
  return match?.[1] || null;
}

function isYouTubeUrl(url) {
  return /^https?:\/\/(www\.)?(youtube\.com\/(watch\?v=|shorts\/|music)|youtu\.be\/)/.test(url);
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

  const ytId = extractYtId(url);
  const fallbackThumbnail = ytId ? `https://i.ytimg.com/vi/${ytId}/hqdefault.jpg` : null;

  let lastError = null;

  for (const api of APIS) {
    if (api.requiresEnv && !process.env[api.requiresEnv]) {
      console.log(`[yt-download] Skip ${api.name}: env ${api.requiresEnv} tidak ada`);
      continue;
    }

    try {
      console.log(`[yt-download] Mencoba API: ${api.name}`);

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 9000);

      const fetchOptions = {
        method: api.method || 'GET',
        signal: controller.signal,
        headers: api.buildHeaders ? api.buildHeaders() : {},
      };

      const body = api.buildBody ? api.buildBody(url) : null;
      if (body) fetchOptions.body = body;

      const response = await fetch(api.buildUrl(url), fetchOptions);
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
    }
  }

  console.error('[yt-download] Semua API gagal:', lastError?.message);
  return res.status(502).json({
    error: 'Semua API sedang tidak tersedia. Coba lagi nanti.',
    detail: lastError?.message,
  });
}
