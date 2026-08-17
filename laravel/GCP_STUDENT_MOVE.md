# Move API off Render → Google Cloud e2-micro (keep Neon + Vercel)

**Goal:** Always-on Laravel API (no sleep).  
**Keep:** Neon database + `omrweb.vercel.app`  
**Replace:** `coc-omr-api.onrender.com`

---

## Part 1 — Create the free VM (browser, ~10 min)

1. Open [https://cloud.google.com/free](https://cloud.google.com/free) and sign up (PH works; card is for verification — set a **budget alert at $1**).
2. Open **Compute Engine → VM instances → Create instance**.
3. Settings:
   - **Name:** `coc-omr-api`
   - **Region:** `us-west1` or `us-central1` (always-free e2-micro only in these)
   - **Machine type:** `e2-micro`
   - **Boot disk:** Ubuntu 22.04 LTS, 30 GB balanced
   - **Firewall:** check **Allow HTTP** and **Allow HTTPS**
4. Create. Wait until status is green.
5. Copy the **External IP** (example: `34.x.x.x`).

Optional but recommended: **VPC network → Firewall** confirm rules allow TCP **22, 80, 443** to this VM.

---

## Part 2 — Put the API on the VM

On your Windows PC (PowerShell):

```powershell
cd d:\omr_app
# Zip only the API folder (exclude vendor if huge — composer will install on server)
Compress-Archive -Path coc-omr-api\* -DestinationPath coc-omr-api-upload.zip -Force
```

Upload + SSH (Google Cloud Console → VM → **SSH** button is easiest):

In the browser SSH window:

```bash
sudo mkdir -p /var/www
cd /tmp
# Upload coc-omr-api-upload.zip via the SSH gear menu "Upload file", then:
sudo apt-get update -qq
sudo apt-get install -y unzip
sudo unzip -o coc-omr-api-upload.zip -d /var/www/coc-omr-api
sudo chown -R www-data:www-data /var/www/coc-omr-api
```

Or clone from GitHub if the API is in a repo:

```bash
sudo apt-get update -qq && sudo apt-get install -y git
sudo mkdir -p /var/www
sudo git clone YOUR_GITHUB_URL /var/www/omr_app
sudo mv /var/www/omr_app/coc-omr-api /var/www/coc-omr-api
```

Run the install script:

```bash
cd /var/www/coc-omr-api
sudo bash deploy/setup_oracle_api.sh
```

(Name is historical — works on any Ubuntu 22.04 VM.)

---

## Part 3 — Point Laravel at Neon (important)

Do **not** rely on the empty local Postgres for long-term data. Use your existing Neon DB.

```bash
sudo nano /var/www/coc-omr-api/.env
```

Set:

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=http://YOUR_EXTERNAL_IP
FRONTEND_URL=https://omrweb.vercel.app
AUTO_VERIFY_EMAIL=true
COC_BOOTSTRAP_ADMIN_EMAILS=your.admin@email.com
DB_CONNECTION=pgsql
DATABASE_URL="postgresql://neondb_owner:PASSWORD@ep-XXXX.ap-southeast-1.aws.neon.tech/neondb?sslmode=require"
```

(Paste your real Neon string. You can leave `DB_HOST` unused if `DATABASE_URL` is set — Laravel reads it.)

Then:

```bash
cd /var/www/coc-omr-api
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan migrate --force
sudo systemctl reload nginx
```

Test in browser:

`http://YOUR_EXTERNAL_IP/up` → should show **Application up**.

---

## Part 4 — Connect Vercel + phone

### Vercel
In Vercel → omr_web → Settings → Environment Variables (Production):

| Key | Value |
|-----|--------|
| `API_BASE_URL` | `http://YOUR_EXTERNAL_IP` |
| `NEXT_PUBLIC_API_BASE_URL` | `http://YOUR_EXTERNAL_IP` |

Redeploy web:

```powershell
cd d:\omr_app\omr_web
npx.cmd vercel deploy --prod --yes
```

### Render
You can **suspend** the Render web service later (stop paying attention to it). Keep Neon.

### Phone APK
Update `secrets.json`:

```json
"API_BASE_URL": "http://YOUR_EXTERNAL_IP"
```

Rebuild APK (phones need the new URL):

```powershell
cd d:\omr_app
flutter build apk --release --dart-define-from-file=secrets.json
```

---

## Part 5 — HTTPS later (recommended)

HTTP works for a pilot. Before wide teacher use, add a free name (DuckDNS) + certbot:

```bash
sudo certbot --nginx -d your-name.duckdns.org
```

Then switch all URLs to `https://...` and rebuild the APK again.

---

## Checklist

- [ ] e2-micro VM in us-west1 / us-central1
- [ ] `/up` works on the external IP
- [ ] `.env` uses Neon `DATABASE_URL`
- [ ] Vercel env points at the new API
- [ ] Web login works without “warming”
- [ ] New APK for phones
- [ ] Budget alert $1 on GCP
- [ ] Suspend Render API when happy

---

## If signup asks for a card

That’s normal. Stay on **e2-micro** in **us-west1/us-central1** only. Set billing budget **$1**. Do not create GPUs, big disks, or extra VMs.
