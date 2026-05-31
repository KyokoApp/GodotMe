import supabase from './db-client.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    if (req.method === 'GET') {
      const { playlist_id } = req.query;
      if (!playlist_id) {
        return res.status(400).json({ error: 'Playlist ID is required' });
      }

      const { data, error } = await supabase
        .from('playlist_tracks')
        .select('*')
        .eq('playlist_id', playlist_id)
        .order('id', { ascending: true });

      if (error) throw error;
      return res.status(200).json(data);
    }

    if (req.method === 'POST') {
      const { playlist_id, song_id, title, artist, album, duration, audio_url } = req.body;
      if (!playlist_id || !song_id || !title) {
        return res.status(400).json({ error: 'Playlist ID, Song ID, and Title are required' });
      }

      const { data, error } = await supabase
        .from('playlist_tracks')
        .insert({
          playlist_id,
          song_id,
          title,
          artist: artist || 'Unknown Artist',
          album: album || 'Unknown Album',
          duration: duration || 0,
          audio_url: audio_url || ''
        })
        .select()
        .single();

      if (error) throw error;
      return res.status(201).json(data);
    }

    if (req.method === 'DELETE') {
      const { playlist_id, song_id } = req.body;
      if (!playlist_id || !song_id) {
        return res.status(400).json({ error: 'Playlist ID and Song ID are required' });
      }

      const { error } = await supabase
        .from('playlist_tracks')
        .delete()
        .eq('playlist_id', playlist_id)
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
