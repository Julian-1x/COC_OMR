# Windows Server production — COC OMR

Permanent deployment on **school-owned Windows Server**. No Vercel, Supabase, or tunnels.

## Production URLs (chosen for COC)

| Service | URL |
|---------|-----|
| Web portal | **http://omr.coc** |
| API | **http://api.omr.coc** |
| APK download | **http://omr.coc/downloads/coc-omr.apk** |

School IT adds DNS **A records** pointing both names to this server (`192.168.x.x` on campus LAN). Until then, run `scripts\setup_coc_hosts.ps1` as Administrator on the server.

HTTPS: add a school certificate later; HTTP is fine on a trusted campus LAN (phones allow cleartext to `omr.coc` in the APK).

---

## 1. What to install on the server

| Software | Version | Notes |
|----------|---------|--------|
| **Windows Server** | 2019 or 2022 | Always-on, static campus IP or DNS |
| **XAMPP** (Apache + PHP) | PHP **8.2+** | You already use 8.2.12 on dev — match on server |
| **PostgreSQL** | 15+ | Recommended. MySQL (in XAMPP) works if IT requires it |
| **Node.js LTS** | 20+ | For the Next.js web portal |
| **Composer** | 2.x | `composer.phar` or Windows installer |
| **NSSM** | latest | Keeps the web portal running as a Windows service |

Optional: **win-acme** for free HTTPS (Let’s Encrypt) if the server has a public hostname.

### PHP extensions (in `php.ini`)

Enable these (uncomment or add):

```ini
extension=curl
extension=fileinfo
extension=mbstring
extension=openssl
extension=pdo_pgsql
extension=pgsql
extension=zip
```

Restart Apache after changes.

---

## 2. Folder layout

Use a fixed path IT can back up:

```text
D:\coc-omr\
  api\              ← coc-omr-api (Laravel; Apache points at api\public)
  web\              ← omr_web (Next.js)
  downloads\        ← coc-omr.apk
  backups\          ← database dumps
```

Copy from your dev repo:

```powershell
# On dev machine — zip and copy to server, or git clone on server
xcopy /E /I d:\omr_app\coc-omr-api D:\coc-omr\api
xcopy /E /I d:\omr_app\omr_web D:\coc-omr\web
```

---

## 3. PostgreSQL

1. Install [PostgreSQL for Windows](https://www.postgresql.org/download/windows/).
2. Open **pgAdmin** or `psql` and run:

```sql
CREATE USER coc_omr WITH PASSWORD 'choose-a-strong-password';
CREATE DATABASE coc_omr OWNER coc_omr;
```

3. Allow local connections only (default). Do **not** expose port 5432 to the internet.

---

## 4. Laravel API

```powershell
cd D:\coc-omr\api
D:\xampp\php\php.exe D:\dev\composer.phar install --no-dev --optimize-autoloader
copy .env.example .env
D:\xampp\php\php.exe artisan key:generate
```

Edit `D:\coc-omr\api\.env`:

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

```powershell
D:\xampp\php\php.exe artisan migrate --force
```

**Permissions:** IIS/Apache user must write to `storage\` and `bootstrap\cache\`. Right-click → Properties → Security → give **Modify** to the account Apache runs as (often `SYSTEM` or a service account).

---

## 5. Apache virtual hosts (XAMPP)

Edit `D:\xampp\apache\conf\extra\httpd-vhosts.conf`. Enable vhosts in `httpd.conf` if not already (`Include conf/extra/httpd-vhosts.conf`).

### API host

```apache
<VirtualHost *:80>
    ServerName api.omr.yourschool.edu
    DocumentRoot "D:/coc-omr/api/public"

    <Directory "D:/coc-omr/api/public">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

### Web portal — reverse proxy to Node

Enable modules in `httpd.conf`:

```apache
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
```

```apache
<VirtualHost *:80>
    ServerName omr.yourschool.edu

    ProxyPreserveHost On
    ProxyPass /downloads/ !
    Alias /downloads "D:/coc-omr/downloads"
    <Directory "D:/coc-omr/downloads">
        Require all granted
    </Directory>

    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
</VirtualHost>
```

Restart Apache from XAMPP Control Panel.

**DNS:** Point `api.omr.yourschool.edu` and `omr.yourschool.edu` to this server’s IP (campus DNS or public DNS).

---

## 6. HTTPS on Windows

### Campus-only (internal CA)

IT installs a school certificate in Windows **Certificate Store** and binds it in Apache (`SSLEngine on`, `SSLCertificateFile`, etc.) or IIS.

### Public hostname (Let’s Encrypt)

Use [win-acme](https://www.win-acme.com/) — it can create bindings for Apache or IIS and auto-renew.

After HTTPS works, set `APP_URL` and `FRONTEND_URL` to `https://...` in `.env`.

---

## 7. Web portal (Next.js as a Windows service)

```powershell
cd D:\coc-omr\web
npm ci
```

Create `D:\coc-omr\web\.env.production`:

```env
API_BASE_URL=https://api.omr.yourschool.edu
NEXT_PUBLIC_API_BASE_URL=https://api.omr.yourschool.edu
```

```powershell
npm run build
```

### NSSM — run on boot

1. Download [NSSM](https://nssm.cc/download).
2. Install service:

```powershell
nssm install CocOmrWeb "C:\Program Files\nodejs\npm.cmd" "start"
nssm set CocOmrWeb AppDirectory D:\coc-omr\web
nssm set CocOmrWeb AppEnvironmentExtra API_BASE_URL=https://api.omr.yourschool.edu NEXT_PUBLIC_API_BASE_URL=https://api.omr.yourschool.edu
nssm start CocOmrWeb
```

Verify: `http://127.0.0.1:3000/login` on the server.

---

## 8. Windows Firewall

Allow inbound **443** (and **80** for redirect) for the web/API hostnames. Block **5432** (PostgreSQL) from outside.

```powershell
New-NetFirewallRule -DisplayName "COC OMR HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
```

---

## 9. Mobile APK

On your **dev PC**, `secrets.json`:

```json
{
  "API_BASE_URL": "https://api.omr.yourschool.edu"
}
```

```powershell
.\scripts\build_release.ps1
```

Copy APK to server:

```powershell
copy build\app\outputs\flutter-apk\app-release.apk D:\coc-omr\downloads\coc-omr.apk
```

Register in database (pgAdmin or `psql`):

```sql
INSERT INTO app_releases (build_number, version_name, download_url, notes, mandatory)
VALUES (41, '1.5.0', 'https://omr.yourschool.edu/downloads/coc-omr.apk', 'Windows Server production', false);
```

---

## 10. Backups (Task Scheduler)

Daily PowerShell script `D:\coc-omr\backup.ps1`:

```powershell
$date = Get-Date -Format "yyyy-MM-dd"
$env:PGPASSWORD = "choose-a-strong-password"
& "C:\Program Files\PostgreSQL\16\bin\pg_dump.exe" -Fc -U coc_omr coc_omr `
  -f "D:\coc-omr\backups\coc_omr_$date.dump"
```

Task Scheduler → daily at 2 AM → run `powershell.exe -File D:\coc-omr\backup.ps1`.

Test a restore before exam season.

---

## 11. Alternative: IIS instead of XAMPP Apache

If IT standardizes on **IIS**:

1. Install **URL Rewrite** and **PHP Manager** (or FastCGI for PHP 8.2).
2. Site 1: physical path `D:\coc-omr\api\public`, URL rewrite rules from Laravel’s `web.config` (generate with `php artisan` or copy from Laravel docs).
3. Site 2: **Application Request Routing (ARR)** reverse proxy to `http://127.0.0.1:3000` for the web portal.
4. Same `.env` files and NSSM service as above.

XAMPP Apache is simpler if you are already comfortable with it.

---

## 12. Smoke test

1. `https://api.omr.yourschool.edu/up` → “Application up”
2. `https://omr.yourschool.edu/login` → register → dashboard
3. Phone on school Wi‑Fi: sign in → offline PIN → **Sync Now** → refresh web
4. Airplane mode on phone: PIN + scan still work

Full checklist: [SMOKE_TEST.md](SMOKE_TEST.md)

---

## 13. Decommission third-party services

| Stop using | Use instead |
|------------|-------------|
| Vercel | `https://omr.yourschool.edu` |
| Supabase | Your PostgreSQL on this server |
| localtunnel / cloudflared | Nothing |

---

## Quick reference — services that must stay running

| Service | How |
|---------|-----|
| Apache (XAMPP) | XAMPP Control Panel → Apache → auto-start via Windows Service if configured |
| PostgreSQL | Windows Service → Automatic |
| Next.js portal | NSSM service `CocOmrWeb` → Automatic |

After a server reboot, teachers should still reach the portal without you logging in manually.
