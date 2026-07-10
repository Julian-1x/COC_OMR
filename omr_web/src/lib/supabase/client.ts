const REMOVED =
  "Supabase was removed from omr_web. Use createBrowserApiClient from @/lib/api/laravel-client.";

export function isSupabaseConfigured(): boolean {
  return false;
}

export function createClient(): never {
  throw new Error(REMOVED);
}
