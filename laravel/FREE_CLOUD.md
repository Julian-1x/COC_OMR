# Free cloud deployment — COC OMR

Run the **web portal** on Vercel (free) and the **Laravel API** on a free host. Phones and browsers work from anywhere — not your PC, not school Wi‑Fi only.

```text
Phones + browsers  →  https://YOUR-APP.vercel.app        (Vercel — free)
                    →  https://YOUR-API.onrender.com      (Render — free, PH-friendly)
```

| Piece | Free host | Typical URL |
|-------|-----------|-------------|
| Web portal | [Vercel Hobby](https://vercel.com) | `https://coc-omr-web.vercel.app` |
| Laravel API + PostgreSQL | See paths below | `https://coc-omr-api.onrender.com` |
| Phone APK | Built on your PC | `API_BASE_URL` in `secrets.json` |

**Cost:** $0/month on free tiers. Trade-offs differ by provider (see below).

---

## Philippines — Oracle not in the country list?

You are not alone. Many developers in the Philippines cannot complete [Oracle Cloud](https://www.oracle.com/cloud/free/) signup (country missing, card rejected, or “unable to complete sign up”). **Skip Oracle.**

Use this order instead:

| Priority | API host | Works from PH? | Long-term free? |
|----------|----------|----------------|-----------------|
| **1 — Start here** | [Render](https://render.com) | Yes | HTTPS included; DB free tier **expires** (~30–90 days); API **sleeps** when idle |
| **2 — Better long-term** | [Google Cloud](https://cloud.google.com/free) e2-micro VM | Usually yes (PH in country list) | Always-free VM in US regions; needs debit/credit card for verification |
| **3 — Best if school helps** | School IT Linux VM | Yes | $0; data stays on campus |
| Optional | Oracle Cloud | Often blocked in PH | Skip if signup fails |

**Recommended for you right now:** **Render (API) + Vercel (web)** — both accept Philippines signups, no server in your room.

---

## Path A — Render API + Vercel web (Philippines-friendly)

### What you accept on free Render

- First request after idle can take **30–60 seconds** (service wakes up)
- Free PostgreSQL **expires** after ~30–90 days — export/backup before exam season, or ask school IT for a VM later
- Fine for **pilot + one semester** if you keep backups

HTTPS is automatic: `https://your-service.onrender.com` — no custom domain required.

### A1 — Push code to GitHub

1. Create a GitHub repo and push this project (or at least the `coc-omr-api/` folder in a repo).
2. Note the repo URL.

### A2 — Render: PostgreSQL (free)

1. Sign up at [render.com](https://render.com) (GitHub login).
2. **New → PostgreSQL** → Name: `coc-omr-db` → Plan: **Free** → Create.
3. Copy the **Internal Database URL** (starts with `postgresql://`).

### A3 — Render: Web Service (Laravel)

1. **New → Web Service** → connect your GitHub repo.
2. Settings:
   - **Root Directory:** `coc-omr-api` (if repo is the full `omr_app` monorepo)
   - **Runtime:** Docker
   - **Plan:** Free
   - **Health Check Path:** `/up`
3. **Environment variables** (add manually):

| Key | Value |
|-----|--------|
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |
| `APP_KEY` | Run locally: `cd coc-omr-api && php artisan key:generate --show` |
| `APP_URL` | `https://YOUR-SERVICE.onrender.com` (update after first deploy with real URL) |
| `DB_CONNECTION` | `pgsql` |
| `DATABASE_URL` | Internal DB URL from A2 |
| `AUTO_VERIFY_EMAIL` | `true` for pilot (no SMTP yet) or `false` if you add mail later |
| `FRONTEND_URL` | Set after Vercel deploy (step A4) |
| `MOBILE_VERIFY_REDIRECT` | `edu.coc.omr://login-callback` |

4. Deploy. When live, open `https://YOUR-SERVICE.onrender.com/up` → should return **200**.

**Optional — reduce cold starts:** add your Render URL to [cron-job.org](https://cron-job.org) (free) to ping `/up` every 10 minutes. Not guaranteed 24/7 awake on free tier, but helps.

### A4 — Vercel: web portal (free)

On your Windows PC:

```powershell
cd d:\omr_app\omr_web
npx vercel@latest login

cd d:\omr_app
.\scripts\deploy_free_cloud.ps1 -ApiUrl "https://YOUR-SERVICE.onrender.com" -UpdateSecrets
```

Note your Vercel URL (e.g. `https://coc-omr-web.vercel.app`).

### A5 — Connect API ↔ web

In **Render** → your web service → **Environment**, set:

```env
FRONTEND_URL=https://YOUR-APP.vercel.app
SANCTUM_STATEFUL_DOMAINS=YOUR-APP.vercel.app,YOUR-SERVICE.onrender.com
APP_URL=https://YOUR-SERVICE.onrender.com
```

Save → Render redeploys.

### A6 — Phone APK

`secrets.json` should already have the Render API URL from step A4. Build:

```powershell
.\scripts\build_release.ps1
```

### A7 — Smoke test

- [ ] `https://YOUR-SERVICE.onrender.com/up` → 200 (may be slow first time)
- [ ] `https://YOUR-APP.vercel.app/login` → loads
- [ ] Register / sign in on web
- [ ] Phone sign-in + **Sync Now**

---

## Path B — Google Cloud e2-micro (longer free run, more setup)

If Render’s DB expiry worries you and Oracle is blocked:

1. Sign up at [cloud.google.com/free](https://cloud.google.com/free) — **Philippines is usually available**; card required for verification, not charged if you stay in free limits.
2. Create an **e2-micro** VM, Ubuntu 22.04, region **us-west1** or **us-central1** (only US regions are always-free).
3. Allow firewall TCP **22, 80, 443**.
4. Copy `coc-omr-api/` to the VM and run:

```bash
sudo bash deploy/setup_oracle_api.sh
```

(Same script works on any Ubuntu VM — name is historical.)

5. Use a free DNS name or school subdomain → certbot for HTTPS.
6. Continue with **Vercel** (step A4) using your `https://api.your-name.example` URL.

Set a **billing budget alert** at ₱0 / $1 in Google Cloud so you get warned before any charge.

---

## Path C — School IT server ($0, no signup blocks)

Ask PHINMA IT for a small Linux VM or existing server:

- Public or campus URL with HTTPS
- Follow [SELF_HOSTED.md](SELF_HOSTED.md)
- Web still on **Vercel free**; only API on school server

Often the cleanest long-term option for a college — no personal credit card.

---

## Path D — Oracle Cloud (only if signup works)

If Philippines appears in Oracle’s country list and card verification passes:

1. [oracle.com/cloud/free](https://www.oracle.com/cloud/free/)
2. Ubuntu VM → `sudo bash deploy/setup_oracle_api.sh`
3. DNS + certbot → Vercel as above

If blocked, use Path A or B — do not fight Oracle for weeks.

---

## Updating after code changes

| What changed | Action |
|--------------|--------|
| `omr_web/` | `.\scripts\deploy_web_vercel.ps1` |
| `coc-omr-api/` | Push to GitHub → Render auto-redeploys (or `git pull` on VM) |
| Flutter app | `.\scripts\build_release.ps1` |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Web “fetch failed” | `API_BASE_URL` on Vercel; `FRONTEND_URL` on Render; wait for cold start |
| API very slow first time | Render free tier waking up — retry after 60s |
| Phone can’t sign in | `API_BASE_URL` must be **https**; rebuild APK |
| Data disappeared | Free Render Postgres expired — restore from backup; move to Path B or C |

---

## Related docs

- [SELF_HOSTED.md](SELF_HOSTED.md) — Linux/nginx (GCP, school VM)
- [SETUP.md](SETUP.md) — Laravel env variables
- [../omr_web/README.md](../omr_web/README.md) — Vercel
- [../DEPLOYMENT.md](../DEPLOYMENT.md) — production checklist
