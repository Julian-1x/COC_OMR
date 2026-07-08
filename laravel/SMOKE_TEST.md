# Laravel cutover — smoke test checklist

Run on **staging** (Laravel API + Vercel preview or production) before teachers install the new APK (`1.5.0+`).

## Automated (CI / dev machine)

- [x] `flutter analyze lib` — no errors
- [x] `flutter test` — all tests pass
- [x] `cd omr_web && npm run build` — production build succeeds

## API server (school staging)

1. Deploy `coc-omr-api/` per [SETUP.md](SETUP.md)
2. `composer install`, `php artisan migrate`, configure SMTP
3. Set `FRONTEND_URL` to your Vercel URL
4. Set `AUTO_VERIFY_EMAIL=false` in production (use real email confirm)

## End-to-end (manual)

| # | Step | Pass |
|---|------|------|
| 1 | Register on **phone** → confirm email (deep link `edu.coc.omr://login-callback?token=...`) | |
| 2 | Register on **web** → confirm email (`/auth/callback`) | |
| 3 | Create offline PIN → reach dashboard | |
| 4 | Import roster + answer key (phone or web) | |
| 5 | Print PDFs at 100% scale | |
| 6 | Scan offline → review queue | |
| 7 | **Sync Now** on phone → data appears on web | |
| 8 | Edit roster/key on web → **Sync Now** on phone | |
| 9 | PIN restore: sign in on second device → cloud PIN applies | |
| 10 | Archive section end-of-term → sync both ways | |
| 11 | School admin read-only view (same `school_name`) | |
| 12 | Airplane mode: PIN unlock + scan still work (no API) | |

## Decommission Supabase (after all pass)

1. Update local `secrets.json`: replace `SUPABASE_*` with `API_BASE_URL` (see `secrets.json.example`)
2. Remove Supabase env vars from Vercel; set `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL`
3. Pause or delete the Supabase project
4. Tell teachers: **sign out**, **register again**, set new PIN, **Sync Now**

## Release notes snippet for teachers

> This update moves your account to the school server. Create a **new account** after updating (old test logins no longer work). Scanning and your offline PIN work the same. Use **Sync Now** when you have Wi‑Fi.
