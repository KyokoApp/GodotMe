import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  'https://larmuwnemgumtndpouxw.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxhcm11d25lbWd1bXRuZHBvdXh3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAyMDQ3MjgsImV4cCI6MjA5NTc4MDcyOH0.w09NG6o-KwGjrLfxbuHF2Zfwv5u2C7eWNTLGfsfhnDU'
);

export default supabase;
