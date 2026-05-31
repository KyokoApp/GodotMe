import supabase from './db-client.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const token = req.headers.authorization?.replace('Bearer ', '');
  let userId = 'anonymous';

  if (token && token !== 'undefined' && token !== 'null') {
    try {
      const { data: { user }, error } = await supabase.auth.getUser(token);
      if (!error && user) {
        userId = user.id;
      }
    } catch (e) {
      console.warn('Token verification failed:', e.message);
    }
  }

  try {
    if (req.method === 'GET') {
      const { data, error } = await supabase
        .from('user_playlists')
        .select('*')
        .eq('user_id', userId)
        .order('id', { ascending: true });
      if (error) throw error;
      return res.status(200).json(data);
    }

    if (req.method === 'POST') {
      const { name, description } = req.body;
      if (!name) {
        return res.status(400).json({ error: 'Playlist name is required' });
      }

      const { data, error } = await supabase
        .from('user_playlists')
        .insert({
          user_id: userId,
          name,
          description: description || '',
          created_at: new Date().toISOString()
        })
        .select()
        .single();

      if (error) throw error;
      return res.status(201).json(data);
    }

    if (req.method === 'DELETE') {
      const { id } = req.body;
      if (!id) {
        return res.status(400).json({ error: 'Playlist ID is required' });
      }

      // Delete tracks first
      await supabase
        .from('playlist_tracks')
        .delete()
        .eq('playlist_id', id);

      const { error } = await supabase
        .from('user_playlists')
        .delete()
        .eq('user_id', userId)
        .eq('id', id);

      if (error) throw error;
      return res.status(200).json({ ok: true });
    }

    res.status(405).json({ error: 'Method not allowed' });
  } catch (err) {
    console.error('API error:', err);
    res.status(500).json({ error: err.message });
  }
}
