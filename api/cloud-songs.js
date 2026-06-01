import supabase from './db-client.js';

const ADMIN_EMAIL = 'kyokomd2006@gmail.com';

// Check if a Cloudinary audio URL still exists (HEAD request)
async function isUrlAlive(url) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(url, { method: 'HEAD', signal: controller.signal });
    clearTimeout(timeout);
    return res.ok; // 200-299 = exists, 404/403 = gone
  } catch (e) {
    // Network error or timeout — assume still alive to avoid false deletes
    return true;
  }
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    if (req.method === 'GET') {
      const { data, error } = await supabase
        .from('cloud_songs')
        .select('*')
        .order('id', { ascending: true });
      if (error) throw error;

      // Validate each song's audio_url against Cloudinary
      // Songs with dead URLs get auto-deleted from Supabase
      const validSongs = [];
      const deleteIds = [];

      await Promise.all(
        (data || []).map(async (song) => {
          if (!song.audio_url) {
            deleteIds.push(song.id);
            return;
          }
          const alive = await isUrlAlive(song.audio_url);
          if (alive) {
            validSongs.push(song);
          } else {
            deleteIds.push(song.id);
            console.log(`[cloud-songs] Auto-removing dead song: "${song.title}" (${song.audio_url})`);
          }
        })
      );

      // Batch delete orphaned records from Supabase
      if (deleteIds.length > 0) {
        const { error: delErr } = await supabase
          .from('cloud_songs')
          .delete()
          .in('id', deleteIds);
        if (delErr) console.error('Failed to auto-delete orphaned songs:', delErr);
      }

      return res.status(200).json(validSongs);
    }

    if (req.method === 'DELETE') {
      // Verify admin via Supabase auth token
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      const token = authHeader.replace('Bearer ', '');
      const { data: { user }, error: authError } = await supabase.auth.getUser(token);
      if (authError || !user) return res.status(401).json({ error: 'Invalid token' });
      if (user.email !== ADMIN_EMAIL) return res.status(403).json({ error: 'Forbidden: admin only' });

      const { id } = req.body || {};
      if (!id) return res.status(400).json({ error: 'Missing song id' });

      const { error: deleteError } = await supabase
        .from('cloud_songs')
        .delete()
        .eq('id', id);
      if (deleteError) throw deleteError;

      return res.status(200).json({ success: true });
    }

    res.status(405).json({ error: 'Method not allowed' });
  } catch (err) {
    console.error('API error:', err);
    res.status(500).json({ error: err.message });
  }
}
