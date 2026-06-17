# COC OMR — Teacher Web Portal

Desk companion for **PHINMA Cagayan de Oro College** teachers. Prep rosters, answer keys, print sheets, and view results. **Scanning stays on the phone app.**

## Setup

1. Install [Node.js LTS](https://nodejs.org/) (18+).
2. Copy env file and add your Supabase keys (same project as the mobile app):

```powershell
cd omr_web
copy .env.local.example .env.local
```

3. In **Supabase → Authentication → URL Configuration**, add redirect URLs:

- `http://localhost:3000/auth/callback`
- Your production URL, e.g. `https://your-app.vercel.app/auth/callback`

4. Install and run:

```powershell
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Features

- Sign in with the same teacher email/password as the mobile app
- **Classes** — browse sections, search, roster CSV, add/remove students
- **Prepare** — import CSV/Excel roster, answer keys (exam date, partial credit, multi-answer), print OMR PDFs, OMR ID handouts
- **Results** — view synced scans, item analysis, export CSV/PDF
- **Settings** — account info, cloud sync diagnostics

No camera scanner on web (by design).

## Deploy to Vercel (free hosting)

**Vercel** hosts the web portal on the internet — like putting your local `localhost:3000` site on a real URL (e.g. `https://coc-omr.vercel.app`). Free tier is enough for school pilots. SSL and updates are automatic.

### One-time setup

1. Create a free account at [vercel.com](https://vercel.com) (GitHub sign-in is easiest).
2. Log in from this machine (once):

```powershell
cd omr_web
npx vercel@latest login
```

3. In **Supabase → Authentication → URL Configuration**, add redirect URLs:

- `http://localhost:3000/auth/callback` (local dev)
- `https://YOUR-VERCEL-URL/auth/callback` (after first deploy — see below)

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
| `SUPABASE_URL` | Same as mobile app |
| `SUPABASE_PUBLISHABLE_KEY` | Same as mobile app |
| `NEXT_PUBLIC_SUPABASE_URL` | Same as `SUPABASE_URL` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Same as `SUPABASE_PUBLISHABLE_KEY` |

After deploy, copy your production URL from the Vercel dashboard and add  
`https://that-url/auth/callback` to Supabase redirect URLs.

### GitHub auto-deploy (recommended)

1. Push this repo to GitHub (include the `omr_web/` folder).
2. In [Vercel](https://vercel.com) → **omr_web** → Settings → Git: connect the repo, set **Root Directory** to `omr_web`.
3. Add the four Supabase env vars in Vercel (Production + Preview).
4. Optional CI deploy via GitHub Actions (`.github/workflows/omr-web.yml`):
   - Vercel → Settings → copy **Project ID** and **Org ID**
   - Vercel → Account → Tokens → create token
   - GitHub repo → Settings → Secrets → add `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`
   - Each push to `main` that touches `omr_web/` builds and deploys automatically.

Or deploy manually:

```powershell
.\scripts\deploy_web_vercel.ps1
```

Keep Supabase on the free tier for pilots; use a weekly ping or unpause if the project sleeps after inactivity.

## Data flow

Phone scans offline → **Sync Now** in app → data appears in this portal.

Web edits (roster, keys) → sync on phone → available for scanning.

## Production smoke test (after deploy)

1. Open `https://omrweb.vercel.app` and sign in with a teacher account.
2. Dashboard shows stat cards (or sync-help card if empty).
3. Phone → Settings → **Sync Now** → refresh web → classes/students appear.
4. Prepare → import roster or edit answer key → save without errors.
5. Results → filters work; Item analysis loads for a subject with scans.
