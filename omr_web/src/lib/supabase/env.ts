const REMOVED =
  "Supabase was removed from omr_web. Use @/lib/api/laravel-client instead.";

export function getSupabaseServerEnv(): never {
  throw new Error(REMOVED);
}

export function getSupabaseClientEnv(): never {
  throw new Error(REMOVED);
}

export function getSupabaseProjectRef(): never {
  throw new Error(REMOVED);
}

export function isSupabaseConfigured(): boolean {
  return false;
}
