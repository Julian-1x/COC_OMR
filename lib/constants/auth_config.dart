/// Deep link Supabase uses after **mobile** email confirmation (and password reset).
///
/// Web sign-up uses `/auth/callback` on the portal instead — see
/// `omr_web/src/lib/auth/redirect.ts`.
///
/// Add this URL in Supabase → Authentication → URL Configuration → Redirect URLs.
const String kAuthRedirectUrl = 'edu.coc.omr://login-callback';
