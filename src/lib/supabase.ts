import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || import.meta.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || import.meta.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

// Create a robust client that gracefully falls back if environment variables are missing
let supabase: any;

if (supabaseUrl && supabaseAnonKey && supabaseUrl !== 'undefined' && supabaseAnonKey !== 'undefined') {
  try {
    supabase = createClient(supabaseUrl, supabaseAnonKey);
  } catch (e) {
    console.error('Failed to initialize Supabase client:', e);
    supabase = createMockSupabase();
  }
} else {
  console.warn('KyokoBeat: Supabase environment variables are missing. Cloud Sync features will be disabled.');
  supabase = createMockSupabase();
}

function createMockSupabase() {
  return {
    auth: {
      getSession: async () => ({ data: { session: null }, error: null }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
      signOut: async () => ({ error: null }),
      signUp: async () => ({ data: { user: null }, error: new Error('Supabase not configured') }),
      signInWithPassword: async () => ({ data: { user: null }, error: new Error('Supabase not configured') }),
      signInWithIdToken: async () => ({ data: { user: null }, error: new Error('Supabase not configured') }),
    },
    from: () => ({
      select: () => ({
        order: () => Promise.resolve({ data: [], error: null }),
        eq: () => ({
          order: () => Promise.resolve({ data: [], error: null })
        }),
        maybeSingle: () => Promise.resolve({ data: null, error: null })
      }),
      insert: () => ({
        select: () => ({
          single: () => Promise.resolve({ data: null, error: null })
        })
      }),
      delete: () => ({
        eq: () => Promise.resolve({ error: null })
      })
    })
  };
}

export { supabase };
export default supabase;
