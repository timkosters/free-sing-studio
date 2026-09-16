// Lazily-created Supabase client for optional practice sync.
//
// Sync is a bonus, never a requirement: with no credentials configured this
// module reports itself unavailable and the app runs exactly as before, still
// keeping every day of practice in localStorage.

// Imported for types only; the implementation is fetched on demand below so
// the auth bundle never lands on someone who just wants to sing.
import type { SupabaseClient } from '@supabase/supabase-js';

// Read through a cast so the app does not need Vite's ambient env types.
const env =
  (import.meta as unknown as { env?: Record<string, string | undefined> })
    .env ?? {};
const url = env.VITE_SUPABASE_URL;
const anonKey = env.VITE_SUPABASE_ANON_KEY;

/** False when the deployment has no Supabase credentials; hides sync entirely. */
export const syncConfigured = Boolean(url && anonKey);

export const PRACTICE_TABLE = 'practice_days';

let client: Promise<SupabaseClient> | null = null;

/**
 * Resolve the client, downloading it the first time it is genuinely needed:
 * when someone opens the sync panel, or when this browser already holds a
 * session. Returns null when sync is not configured at all.
 */
export function supabase(): Promise<SupabaseClient> | null {
  if (!url || !anonKey) return null;
  if (!client)
    client = import('@supabase/supabase-js').then(({ createClient }) =>
      createClient(url, anonKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          // There is no callback route: the code is typed into the page.
          detectSessionInUrl: false,
        },
      }),
    );
  return client;
}

/**
 * Whether this browser already holds a session, answered from localStorage so
 * a first visit never pays to download the auth client just to find out it is
 * signed out. Supabase stores its session under `sb-<project ref>-auth-token`.
 */
export function hasStoredSession(): boolean {
  if (!syncConfigured) return false;
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key?.startsWith('sb-') && key.endsWith('-auth-token')) return true;
    }
  } catch {}
  return false;
}
