declare const jsmediatags: any;

export interface SongMetadata {
  title: string;
  artist: string;
  album: string;
  duration: number;
  cover: string | null;
}

// Helper to get audio duration using a temporary HTMLAudioElement
export function getAudioDuration(file: File): Promise<number> {
  return new Promise((resolve) => {
    const audio = new Audio();
    const url = URL.createObjectURL(file);
    audio.src = url;
    
    const timeout = setTimeout(() => {
      resolve(0);
      URL.revokeObjectURL(url);
    }, 4000); // 4 seconds safety timeout

    audio.addEventListener('loadedmetadata', () => {
      clearTimeout(timeout);
      resolve(audio.duration || 0);
      URL.revokeObjectURL(url);
    });

    audio.addEventListener('error', () => {
      clearTimeout(timeout);
      resolve(0);
      URL.revokeObjectURL(url);
    });
  });
}

// Helper to parse ID3 tags using jsmediatags
export function parseID3Tags(file: File): Promise<Partial<SongMetadata>> {
  return new Promise((resolve) => {
    if (typeof jsmediatags === 'undefined') {
      console.warn('jsmediatags is not loaded from CDN');
      resolve({});
      return;
    }

    jsmediatags.read(file, {
      onSuccess: (tag: any) => {
        const tags = tag.tags;
        let cover: string | null = null;

        if (tags.picture) {
          try {
            const { data, format } = tags.picture;
            let binary = '';
            const bytes = new Uint8Array(data);
            const len = bytes.byteLength;
            for (let i = 0; i < len; i++) {
              binary += String.fromCharCode(bytes[i]);
            }
            const base64 = btoa(binary);
            cover = `data:${format};base64,${base64}`;
          } catch (e) {
            console.error('Failed to parse cover art:', e);
          }
        }

        resolve({
          title: tags.title || undefined,
          artist: tags.artist || undefined,
          album: tags.album || undefined,
          cover,
        });
      },
      onError: (error: any) => {
        console.warn('ID3 tag reading failed, using defaults:', error);
        resolve({});
      }
    });
  });
}

// Combined metadata extractor
export async function extractMetadata(file: File): Promise<SongMetadata> {
  const baseName = file.name.replace(/\.[^/.]+$/, ""); // Remove extension
  
  // Start both tasks: duration and ID3 tags
  const [duration, tags] = await Promise.all([
    getAudioDuration(file),
    parseID3Tags(file)
  ]);

  // Handle Title parsing from filename (e.g. "Artist - Title" format)
  let parsedArtist = tags.artist || 'Unknown Artist';
  let parsedTitle = tags.title || baseName;

  if (!tags.title && baseName.includes('-')) {
    const parts = baseName.split('-');
    parsedArtist = parts[0].trim();
    parsedTitle = parts.slice(1).join('-').trim();
  }

  return {
    title: parsedTitle,
    artist: parsedArtist,
    album: tags.album || 'Unknown Album',
    duration: duration || 0,
    cover: tags.cover || null,
  };
}
