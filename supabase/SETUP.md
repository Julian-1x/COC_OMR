# Supabase setup for COC OMR

One-time setup. Teachers never open Supabase — only you (developer).

## 1. Create a project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) and sign in.
2. **New project** → name it e.g. `coc-omr`.
3. Choose a region close to the Philippines if available.
4. Set a strong database password (save it in a password manager).

Wait until the project status is **Healthy**.

## 2. Enable email login

1. **Authentication** → **Providers** → **Email**
2. Turn **Email** ON.
3. You can keep **Confirm email** **ON** (recommended). The app uses a phone deep link — configure step 4.
4. **Authentication** → **URL Configuration**:
   - **Site URL:** `https://omrweb.vercel.app` (web portal — used when redirect is missing)
   - **Redirect URLs** — add every line (Supabase only allows listed URLs):
     ```
     edu.coc.omr://login-callback
     https://omrweb.vercel.app/auth/callback
     http://localhost:3000/auth/callback
     ```
   - **How redirects work:**
     - Register on **phone** → confirmation link opens the app (`edu.coc.omr://login-callback`)
     - Register on **web** → confirmation link returns to `/auth/callback` on the same site
5. Save.

## 3. Run the database schema

1. **SQL Editor** → **New query**
2. Open `supabase/schema.sql` from this repo, copy all of it, paste into the editor.
3. Click **Run**.

You should see tables: `teacher_profiles`, `sections`, `students`, `subjects`, `scan_results`, `deadlines`, `scan_warnings`.

**Already deployed?** Run these once in order:

1. `supabase/add_pin_sync.sql` — offline PIN restore on new phones
2. `supabase/add_section_archive.sql` — end-of-term archive columns on `sections`

## 4. Copy API keys for the app

1. **Project Settings** → **API**
2. Copy:
   - **Project URL** → use as `SUPABASE_URL`
   - **publishable** key (or **anon public** key on older dashboards) → use as `SUPABASE_PUBLISHABLE_KEY`

Do **not** put the `service_role` / secret key in the mobile app. That key is for server-side admin only.

## 5. Put keys in `secrets.json` (local, not in git)

From the project root:

```powershell
copy secrets.json.example secrets.json
```

Edit `secrets.json`:

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "eyJ... or sb_publishable_...",
  "SENTRY_DSN": "",
  "SENTRY_ENVIRONMENT": "production"
}
```

## 6. Run or build the app

```powershell
.\scripts\run.ps1
.\scripts\build_release.ps1
```

Keys are loaded automatically from `secrets.json`. You do not type `--dart-define` each time.

In Cursor/VS Code, use the **OMR App - Supabase** launch config (also uses `secrets.json`).

## 7. Smoke test

1. Install or run the app.
2. **Register** a test teacher (needs internet).
3. Create offline PIN → open Dashboard.
4. **Settings** → **Sync Now** — should succeed with 0 or more items.
5. In Supabase **Table Editor**, check `teacher_profiles` for the new row.

## What syncs to Supabase

| Data | Synced |
|------|--------|
| Teacher profile | Yes |
| Sections, roster, students | Yes |
| Answer keys / subjects | Yes |
| Scan scores and answers (JSON) | Yes |
| Scan photos | **No** (phone only) |

## Free tier notes

- Supabase free tier is enough for a single-school production deployment at typical class sizes.
- Watch **Database** size and **Auth** monthly active users in the dashboard.
- Back up: teachers should **Sync Now** after exams; you can export tables from the dashboard if needed.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Sign-in disabled in app | `secrets.json` missing or wrong; rebuild APK with `build_release.ps1` |
| Row-level security error | Re-run `schema.sql` |
| Email not confirmed | Open the confirmation email; phone links open the app, web links return to the portal. If you see **localhost** on the phone, fix **URL Configuration** in step 2.4 |
| Registration works, sync fails | Check internet; verify tables exist in Table Editor |
| Web portal empty but phone has data | Same email on phone + web; tap **Sync Now** on phone; use web **Settings → Open sync check** |

## School admin (web portal)

1. Run `supabase/add_admin_rls.sql` in the SQL Editor (after `schema.sql`).
2. Promote an IT lead or coordinator:

```sql
update public.teacher_profiles
set role = 'school_admin'
where id = 'YOUR-AUTH-USER-UUID';
```

3. Ensure `school_name` matches for all teachers at your campus (same string in profile).
4. Sign in at the web portal → **Admin** in the sidebar (read-only school overview).
