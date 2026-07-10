const REMOVED =
  "Supabase was removed from omr_web. Use createServerApiClient from @/lib/api/laravel-client.";

export async function createClient(): Promise<never> {
  throw new Error(REMOVED);
}
