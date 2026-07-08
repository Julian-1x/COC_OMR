# Self-hosted production — COC OMR

Run **everything on school-owned infrastructure**: Laravel API, PostgreSQL, web portal, and APK downloads. No Vercel, Supabase, or temporary tunnels.

## What runs where

```text
Teachers (phones)  ──HTTPS──►  api.omr.yourschool.edu   (Laravel API)
Teachers (browser) ──HTTPS──►  omr.yourschool.edu       (Next.js web portal)
                              └── same server or two VMs behind school firewall
```

| Component | Technology | Typical URL |
|-----------|------------|-------------|
| API + auth + sync | Laravel 11 (`coc-omr-api/`) | `https://api.omr.yourschool.edu` |
| Web portal | Next.js (`omr_web/`) | `https://omr.yourschool.edu` |
| Database | PostgreSQL 15+ | localhost only |
| APK file | Static file on nginx | `https://omr.yourschool.edu/downloads/coc-omr.apk` |

Phones only need **`API_BASE_URL`** baked into the APK. Scanning stays offline on the device.

---

## 1. Server you need

**Recommended:** Ubuntu 22.04 LTS VM or physical box on campus (8 GB RAM, 2 CPU, 40 GB disk).

Install:

```bash
sudo apt update
sudo apt install -y nginx postgresql php8.2-fpm php8.2-{cli,mbstring,xml,curl,zip,bcmath,pgsql,pdo-pgsql} \
  composer nodejs npm certbot python3-certbot-nginx
```

**Windows + XAMPP** works for a pilot (you already have PHP 8.2.12 at `D:\xampp`), but Linux + nginx is easier for 24/7 production, HTTPS, and backups. Use XAMPP only if IT insists on Windows.

---

## 2. DNS (school IT)

Point two hostnames at the server’s public or campus IP:

| Hostname | Purpose |
|----------|---------|
| `api.omr.yourschool.edu` | Laravel API |
| `omr.yourschool.edu` | Web portal (+ APK download folder) |

If teachers are **campus-only**, these can be internal DNS names (e.g. `omr.coc`) with a school CA certificate.

---

## 3. PostgreSQL

```bash
sudo -u postgres psql
```

```sql
CREATE USER coc_omr WITH PASSWORD 'choose-a-strong-password';
CREATE DATABASE coc_omr OWNER coc_omr;
\q
```

---

## 4. Deploy Laravel API

On the server:

```bash
sudo mkdir -p /var/www/coc-omr-api
sudo chown $USER:www-data /var/www/coc-omr-api
```

Copy the `coc-omr-api/` folder from this repo (git clone, rsync, or zip). Then:

```bash
cd /var/www/coc-omr-api
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate
```

Edit `/var/www/coc-omr-api/.env`:

```env
APP_NAME="COC OMR API"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://api.omr.yourschool.edu

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=coc_omr
DB_USERNAME=coc_omr
DB_PASSWORD=choose-a-strong-password

AUTO_VERIFY_EMAIL=false

FRONTEND_URL=https://omr.yourschool.edu
MOBILE_VERIFY_REDIRECT=edu.coc.omr://login-callback

SANCTUM_STATEFUL_DOMAINS=omr.yourschool.edu,api.omr.yourschool.edu

MAIL_MAILER=smtp
MAIL_HOST=mail.yourschool.edu
MAIL_PORT=587
MAIL_USERNAME=noreply@yourschool.edu
MAIL_PASSWORD=...
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@yourschool.edu
MAIL_FROM_NAME="COC OMR"
```

```bash
php artisan migrate --force
sudo chown -R www-data:www-data storage bootstrap/cache
sudo chmod -R ug+rwx storage bootstrap/cache
```

### Nginx — API vhost

`/etc/nginx/sites-available/coc-omr-api`:

```nginx
server {
    listen 80;
    server_name api.omr.yourschool.edu;
    root /var/www/coc-omr-api/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/coc-omr-api /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d api.omr.yourschool.edu
```

Health check: `curl https://api.omr.yourschool.edu/up`

---

## 5. Deploy web portal (Next.js)

```bash
sudo mkdir -p /var/www/omr_web
# copy omr_web/ from repo
cd /var/www/omr_web
npm ci
```

Create `/var/www/omr_web/.env.production`:

```env
API_BASE_URL=https://api.omr.yourschool.edu
NEXT_PUBLIC_API_BASE_URL=https://api.omr.yourschool.edu
```

```bash
npm run build
```

Run with **PM2** (keeps it running after reboot):

```bash
sudo npm install -g pm2
pm2 start npm --name omr-web -- start
pm2 save
pm2 startup   # run the command it prints
```

### Nginx — web vhost

`/etc/nginx/sites-available/omr-web`:

```nginx
server {
    listen 80;
    server_name omr.yourschool.edu;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /downloads/ {
        alias /var/www/omr-downloads/;
        add_header Content-Disposition 'attachment';
    }
}
```

```bash
sudo mkdir -p /var/www/omr-downloads
sudo ln -s /etc/nginx/sites-available/omr-web /etc/nginx/sites-enabled/
sudo certbot --nginx -d omr.yourschool.edu
```

Open **https://omr.yourschool.edu/login** and register a test teacher.

---

## 6. Mobile APK

On your dev machine, set `secrets.json`:

```json
{
  "API_BASE_URL": "https://api.omr.yourschool.edu"
}
```

```powershell
.\scripts\build_release.ps1
```

Copy `build\app\outputs\flutter-apk\app-release.apk` to the server:

```bash
scp app-release.apk server:/var/www/omr-downloads/coc-omr.apk
```

Register the release in the database:

```sql
INSERT INTO app_releases (build_number, version_name, download_url, notes, mandatory)
VALUES (41, '1.5.0', 'https://omr.yourschool.edu/downloads/coc-omr.apk', 'Laravel production', false);
```

Teachers install from that URL or USB/MDM.

---

## 7. School admin account

After a teacher registers:

```sql
UPDATE teacher_profiles
SET role = 'school_admin'
WHERE id = 'USER-UUID-FROM-users-TABLE';
```

---

## 8. Backups (non-negotiable)

Daily cron as `postgres`:

```bash
pg_dump -Fc coc_omr > /backups/coc_omr_$(date +\%F).dump
```

Test a restore once before exam season.

---

## 9. Leave third-party hosting

| Remove | Replace with |
|--------|----------------|
| Vercel (`omrweb.vercel.app`) | `https://omr.yourschool.edu` |
| Supabase project | Pause/delete after cutover |
| localtunnel / cloudflared | Nothing — API is on your server |
| `SUPABASE_*` env vars | `API_BASE_URL` only |

Cutover checklist: [SMOKE_TEST.md](SMOKE_TEST.md)

---

## 10. Windows Server

**Recommended for COC:** full guide at [WINDOWS_SERVER.md](WINDOWS_SERVER.md) — XAMPP Apache, PostgreSQL, NSSM for Next.js, HTTPS, backups.

Summary: same two URLs (`api.omr…` + `omr…`), no Linux required.

---

## Quick smoke test

1. `https://api.omr.yourschool.edu/up` → “Application up”
2. Register on web → login → dashboard
3. Phone: same account → offline PIN → **Sync Now** → data on web
4. Airplane mode: PIN unlock + scan still work
