# Move API to Singapore (same Neon DB)

**Why:** Neon is in Singapore; the current Render API is in the US. That alone costs ~1.6s per DB connection and ~0.5s per query.

**Goal:** New Render web service in **Singapore** → same Neon database → update Vercel + APK → delete old US service.

**Cost:** Keep **one** paid web service (~$7). Do **not** leave old + new both on Starter.

---

## Before you start

1. Open [Render Dashboard](https://dashboard.render.com) → old service `coc-omr-api`.
2. **Environment** → open a notepad and copy **every** env var (especially):
   - `DATABASE_URL` / `DB_URL` (Neon — must be the same)
   - `APP_KEY` (must be the **same** as old — do not generate a new one)
   - `APP_URL` (you will change this to the new hostname later)
   - Mail / Turnstile / captcha / `FRONTEND_URL` / `SANCTUM_STATEFUL_DOMAINS`
   - Any `COC_BOOTSTRAP_APPROVE_EMAILS` or admin bootstrap keys
3. Keep the old service **running** until the new one passes smoke tests.

---

## Step 1 — Create Singapore web service

1. Render → **New** → **Web Service**.
2. Connect repo `Julian-1x/COC_OMR` (branch `main`).
3. Settings:
   - **Name:** `coc-omr-api-sg` (temporary name; rename later if you want)
   - **Region:** **Singapore**
   - **Root Directory:** `coc-omr-api`
   - **Runtime:** **Docker**
   - **Instance type:** **Starter** (~$7) — same as what you pay now (not Free, or it will sleep)
   - **Health Check Path:** `/up`
4. Paste env vars from the notepad.
5. Set / fix these after you know the new URL (or set placeholders then edit):

| Key | Value |
|-----|--------|
| `APP_URL` | `https://YOUR-NEW-SERVICE.onrender.com` |
| `FRONTEND_URL` | `https://omrweb.vercel.app` |
| `SANCTUM_STATEFUL_DOMAINS` | `omrweb.vercel.app,YOUR-NEW-SERVICE.onrender.com` |
| `DATABASE_URL` | **Exact same Neon URL** as the old service |
| `DB_URL` | Same as `DATABASE_URL` |
| `DB_CONNECTION` | `pgsql` |
| `CACHE_STORE` | `file` |
| `SESSION_DRIVER` | `file` |
| `APP_KEY` | **Same as old service** |

6. **Do not** create a new Render PostgreSQL. Neon stays as-is.
7. Deploy. Wait until status is Live.

### Confirm Singapore + speed

```text
https://YOUR-NEW-SERVICE.onrender.com/up
https://YOUR-NEW-SERVICE.onrender.com/api/health/db-latency
```

`db-latency` should show:
- `db_host_masked` still `***.….ap-southeast-1.aws.neon.tech`
- `connect_ms` and `per_query_ms` much lower than before (target: connect under ~200ms, per query under ~50ms — often better)

If still ~500ms/query, the service is not in Singapore — check Region on the service page.

---

## Step 2 — Point Vercel at the new API

In Vercel → `omr_web` project → **Settings → Environment Variables**:

- `API_BASE_URL` = `https://YOUR-NEW-SERVICE.onrender.com`
- `NEXT_PUBLIC_API_BASE_URL` = same value

Redeploy production (or run from PC):

```powershell
cd d:\omr_app
.\scripts\deploy_web_vercel.ps1
```

Smoke: https://omrweb.vercel.app/login → MFA → desk should feel much faster.

---

## Step 3 — Point the phone APK at the new API

Edit `secrets.json`:

```json
{
  "API_BASE_URL": "https://YOUR-NEW-SERVICE.onrender.com",
  "WEB_BASE_URL": "https://omrweb.vercel.app"
}
```

Build and install:

```powershell
cd d:\omr_app
.\scripts\build_release.ps1
```

Teachers reinstall this APK (you already OK with that).

---

## Step 4 — Delete the old US service

Only after:

- [ ] `/up` on **new** URL is 200
- [ ] `db-latency` looks fast
- [ ] Web login + desk works on Vercel
- [ ] Phone sign-in works on new APK

Then: old `coc-omr-api` (US) → **Settings → Delete Web Service**.

Optional: rename `coc-omr-api-sg` → `coc-omr-api` in Render (cosmetic; URL stays the `*.onrender.com` hostname Render gave you unless you add a custom domain).

---

## Step 5 — Warming (optional)

Update cron-job.org (or similar) to ping:

`https://YOUR-NEW-SERVICE.onrender.com/up`

every 10 minutes so Starter stays warm.

---

## Rollback

If something breaks: set Vercel + `secrets.json` back to `https://coc-omr-api.onrender.com` while the old service still exists, redeploy web, rebuild APK.
