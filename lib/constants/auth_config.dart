/// Deep link used after **mobile** email confirmation.
///
/// Web sign-up uses `/auth/callback` on the portal instead — see
/// `omr_web/src/lib/auth/redirect.ts`.
///
/// Laravel should redirect verified users to this URL with `?token=...`.
const String kAuthRedirectUrl = 'edu.coc.omr://login-callback';
