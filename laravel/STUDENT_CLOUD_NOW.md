# Student cloud — do this now (Neon + Render free)

Your stack: **Neon DB** + **Render API** + **Vercel web** (`omrweb.vercel.app`).

Free Render **sleeps**. That causes slow loads, 502s, and “This page couldn’t load.”

## Already done
- [x] Neon database created
- [x] Render pointed at Neon
- [x] cron-job.org pinging `https://coc-omr-api.onrender.com/up`

## You do next (about 10 minutes)

### 1. Render environment
Open Render → **coc-omr-api** → **Environment**. Set:

| Key | Value |
|-----|--------|
| `AUTO_VERIFY_EMAIL` | `true` |
| `COC_BOOTSTRAP_ADMIN_EMAILS` | your admin email |
| `FRONTEND_URL` | `https://omrweb.vercel.app` |
| `APP_URL` | `https://coc-omr-api.onrender.com` |
| `DB_CONNECTION` | `pgsql` |
| `DATABASE_URL` / `DB_URL` | Neon connection string |

Save and wait until deploy is **Live**.

### 2. Wake the API, then open the web
1. Open https://coc-omr-api.onrender.com/up → wait for **Application up**
2. Open https://omrweb.vercel.app/login
3. Register with the bootstrap admin email → Sign in

### 3. If dashboard errors
1. Open `/up` again until green
2. Reload the dashboard
3. Or wait for cron (every ~10 min) to keep the API warm

### 4. Deploy web fixes (from your PC)
Fixes redirect loops + softer dashboard when the API is sleeping:

```powershell
cd d:\omr_app\omr_web
npx vercel login
npx vercel deploy --prod --yes
```

### 5. Phone
Same email/password → create PIN → Sync when Wi‑Fi works. No new APK needed.

## Habit
Before using the site: open `/up` once, then the portal.
