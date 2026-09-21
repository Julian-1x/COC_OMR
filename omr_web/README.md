# COC OMR — Teacher Web Portal

Desk companion for **PHINMA Cagayan de Oro College** teachers. Prep rosters, answer keys, print sheets, and view results. **Scanning stays on the phone app.**

## Setup

1. Install [Node.js LTS](https://nodejs.org/) (18+).
2. Start the Laravel API (`coc-omr-api`) — see `coc-omr-api/README.md`.
3. Copy env file and point at your API:

```powershell
cd omr_web
copy .env.local.example .env.local
```

Edit `.env.local` so `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL` are the same Laravel URL (no trailing slash).

4. Install and run:

```powershell
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

Set `FRONTEND_URL=http://localhost:3000` in the Laravel API `.env` so email verification links return to `/auth/callback`.

### Exam week — keep the API awake

Free hosts may sleep. Before exam mornings:

```powershell
.\scripts\keep_api_awake.ps1 -ApiBaseUrl https://your-api.example.com
```

Prefer an always-on API host for production exam days.

## Features

- Sign in with the same teacher email/password as the mobile app
- **Classes** — browse sections, search, roster CSV, add/remove students
- **Prepare** — import CSV/Excel roster, answer keys (exam date, partial credit, multi-answer), print OMR PDFs, OMR ID handouts
- **Results** — view synced scans, item analysis, export CSV/PDF
- **Settings** — account info, cloud sync diagnostics

No camera scanner on web (by design).

## Security notes (web)

- Auth token cookie (`coc_api_token`) is **httpOnly**. Browser pages call the school API through same-origin `/api/laravel/*` (BFF), so page scripts cannot read the bearer token.
- Teachers stay **pending** until a school admin approves them.
- Super-admin account delete requires typing the teacher email, then a second confirm.

## Print / key integrity

- Web print supports **standard 30–100** sheets and **synced custom layouts** from the phone (same scan geometry).
- Custom print uses the phone’s exam-ready gates: lengthwise full / legacy half / quarter only; A–F choices; dense full-page when needed; multi-up tiling for half/quarter.
- Answer keys show **Shared / One section / No section** badges; print PDFs include `SHARED KEY` or `THIS SECTION ONLY`.
- Print is blocked when the section is not on the key, the key is incomplete, or the custom grid failed to sync / is no longer scannable.
- Always print at **100% scale (Actual size)**. After changing OMR geometry, re-validate on a real printer + phone scan.

## Deploy to Vercel (free hosting)

**Vercel** hosts the web portal on the internet — like putting your local `localhost:3000` site on a real URL (e.g. `https://coc-omr.vercel.app`). Free tier is enough for school pilots. SSL and updates are automatic.

### One-time setup

1. Create a free account at [vercel.com](https://vercel.com) (GitHub sign-in is easiest).
2. Log in from this machine (once):

```powershell
cd omr_web
npx vercel@latest login
```

3. In the Laravel API `.env`, set `FRONTEND_URL` to your web portal URL (e.g. `http://localhost:3000` for local dev, or your Vercel URL after deploy).

### Deploy

From the repo root:

```powershell
.\scripts\deploy_web_vercel.ps1
```

Or manually from `omr_web`:

```powershell
npm run build
npx vercel@latest deploy --prod
```

Set these **Environment Variables** in the Vercel project (Settings → Environment Variables) if not using the script:

| Variable | Value |
|----------|--------|
| `API_BASE_URL` | Your Laravel API URL, e.g. `https://api.yourschool.edu` |
| `NEXT_PUBLIC_API_BASE_URL` | Same as `API_BASE_URL` |

After deploy, set `FRONTEND_URL` on the Laravel API to your Vercel URL so email verification redirects work.

### GitHub auto-deploy (recommended)

1. Push this repo to GitHub (include the `omr_web/` folder).
2. In [Vercel](https://vercel.com) → **omr_web** → Settings → Git: connect the repo, set **Root Directory** to `omr_web`.
3. Add the two API env vars in Vercel (Production + Preview).
4. Optional CI deploy via GitHub Actions (`.github/workflows/omr-web.yml`):
   - Vercel → Settings → copy **Project ID** and **Org ID**
   - Vercel → Account → Tokens → create token
   - GitHub repo → Settings → Secrets → add `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`
   - Each push to `main` that touches `omr_web/` builds and deploys automatically.

Or deploy manually:

```powershell
.\scripts\deploy_web_vercel.ps1
```

Keep the Laravel API running for pilots; use a weekly ping or process manager if the server sleeps after inactivity.

## Data flow

Phone scans offline → **Sync Now** in app → data appears in this portal.

Web edits (roster, keys) → sync on phone → available for scanning.

## Production smoke test (after deploy)

1. Open `https://omrweb.vercel.app` and sign in with a teacher account.
2. Dashboard shows stat cards (or sync-help card if empty).
3. Phone → Settings → **Sync Now** → refresh web → classes/students appear.
4. Prepare → import roster or edit answer key → save without errors.
5. Results → filters work; Item analysis loads for a subject with scans.
