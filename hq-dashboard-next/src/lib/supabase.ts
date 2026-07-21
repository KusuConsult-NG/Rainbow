import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://wpffwoblxuogemxcqpep.supabase.co';
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_9ufgK7BJ8Zy8x7-K133NRQ_8myILNuw';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '***REMOVED-SECRET***';

// Browser / Public Client
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Admin / Service Role Client (for backend / admin operations)
export const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});
