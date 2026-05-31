import supabase from './db-client.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();

  // Extract token from Authorization header if present
  const token = req.headers.authorization?.replace('Bearer ', '');
  let userId = 'anonymous';

  if (token && token !== 'undefined' && token !== 'null') {
    try {
      const { data: { user }, error } = await supabase.auth.getUser(token);
      if (!error && user) {
        userId = user.id;
      }
    } catch (e) {
      console.warn('Token verification failed, using fallback or anonymous:', e.message);
    }
  }

  try {
    if (req.method === 'GET') {
      const { data, error } = await supabase
        .from('user_favorites')
        .select('*')
        .eq('user_id', userId)
        .order('id', { ascending: false });
      if (error) throw error;
      return res.status(200).json(data);
    }

    if (req.method === 'POST') {
      const { song_id, title, artist, album, duration, audio_url, cover_url } = req.body;
      if (!song_id || !title) {
        return res.status(400).json({ error: 'Song ID and Title are required' });
      }

      // Check if already favorited
      const { data: existing } = await supabase
        .from('user_favorites')
        .select('*')
        .eq('user_id', userId)
        .eq('song_id', song_id)
        .maybeSingle();

      if (existing) {
        return res.status(200).json(existing);
      }

      const { data, error } = await supabase
        .from('user_favorites')
        .insert({
          user_id: userId,
          song_id,
          title,
          artist: artist || 'Unknown Artist',
          album: album || 'Unknown Album',
          duration: duration || 0,
          audio_url: audio_url || '',
          cover_url: cover_url || '',
          created_at: new Date().toISOString()
        })
        .select()
        .single();

      if (error) throw error;
      return res.status(201).json(data);
    }

    if (req.method === 'DELETE') {
      const { song_id } = req.body;
      if (!song_id) {
        return res.status(400).json({ error: 'Song ID is required' });
      }

      const { error } = await supabase
        .from('user_favorites')
        .delete()
        .eq('user_id', userId)
        .eq('song_id', song_id);

      if (error) throw error;
      return res.status(200).json({ ok: true });
    }

    res.status(405).json({ error: 'Method not allowed' });
  } catch (err) {
    console.error('API error:', err);
    res.status(500).json({ error: err.message });
  }
}
