# COC OMR Laravel API — School setup

Deploy the API at `coc-omr-api/` to replace Supabase for teacher auth, mobile sync, and the web portal.

## 1. Server requirements

- PHP 8.2+ with extensions: `pdo`, `pdo_sqlite` or `pdo_pgsql`, `mbstring`, `openssl`, `tokenizer`, `xml`, `ctype`, `json`, `bcmath`
- Composer 2.x
- PostgreSQL recommended for production (SQLite is fine for a single-machine pilot)

## 2. Install on the server

```bash
cd /var/www/coc-omr-api
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate
```

### SQLite (small pilot)

```bash
touch database/database.sqlite
# .env
DB_CONNECTION=sqlite
DB_DATABASE=/var/www/coc-omr-api/database/database.sqlite
```

### PostgreSQL (recommended)

```env
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=coc_omr
DB_USERNAME=coc_omr
DB_PASSWORD=your-secure-password
```

```bash
php artisan migrate --force
```

## 3. Environment

| Variable | Purpose |
|----------|---------|
| `APP_URL` | Public API URL, e.g. `https://api.school.edu` |
| `APP_DEBUG` | `false` in production |
| `AUTO_VERIFY_EMAIL` | `true` only for dev; production should be `false` |
| `FRONTEND_URL` | Web portal origin, e.g. `https://omrweb.vercel.app` |
| `MOBILE_VERIFY_REDIRECT` | `edu.coc.omr://login-callback` |
| `MAIL_*` | SMTP for verification and password reset |
| `SANCTUM_STATEFUL_DOMAINS` | Include your web portal host |

Generate `APP_KEY` once per environment. Never commit `.env`.

## 4. Web server

Point the vhost document root to `coc-omr-api/public`.

**Nginx (snippet)**

```nginx
root /var/www/coc-omr-api/public;
index index.php;
location / {
    try_files $uri $uri/ /index.php?$query_string;
}
location ~ \.php$ {
    fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
    include fastcgi_params;
}
```

Health check: `GET /up`

## 5. CORS

`config/cors.php` allows:

- `http://localhost:3000` (local Next.js)
- `https://omrweb.vercel.app` (production web portal)

Add your school’s custom domain to `allowed_origins` before deploy.

## 6. School admin accounts

After a teacher registers, IT can promote them:

```sql
UPDATE teacher_profiles
SET role = 'school_admin'
WHERE id = 'USER-UUID-HERE';
```

Admins get **read-only** visibility into exam data for all teachers with the same `school_name`. They cannot modify another teacher’s sections, students, or scans.

## 7. Mobile app configuration

Point the Flutter app and web portal at this API (`API_BASE_URL` in `secrets.json` and Vercel env). Sync endpoints under `/api/sync/*` match the mobile upsert keys:

- sections: `(owner_teacher_id, name)`
- students: `(owner_teacher_id, school_id)`
- subjects: `(owner_teacher_id, local_id)`
- deadlines: `(owner_teacher_id, local_id)`

## 8. Web portal configuration

Set the Next.js env to the API base URL and use Bearer tokens from `/api/login`. Dashboard and CRUD routes are under `/api/sections`, `/api/students`, etc.

## 9. APK release banner

After each production APK build:

```sql
INSERT INTO app_releases (build_number, version_name, download_url, notes, mandatory)
VALUES (3, '1.0.2', 'https://your-cdn/coc-omr.apk', 'Exam-day fixes', false);
```

Mobile reads `GET /api/app-releases/latest`.

## 10. Post-deploy checklist

- [ ] `php artisan migrate --force`
- [ ] `APP_DEBUG=false`
- [ ] `AUTO_VERIFY_EMAIL=false`
- [ ] Mail sending works (register a test teacher)
- [ ] CORS allows your web portal domain
- [ ] HTTPS on API and portal
- [ ] File permissions: `storage/` and `bootstrap/cache/` writable by PHP

## 11. Backups

Back up the database daily. Teacher PIN hashes, answer keys, and scan results are exam-critical data.

For PostgreSQL:

```bash
pg_dump -Fc coc_omr > coc_omr_$(date +%F).dump
```

For SQLite, copy `database/database.sqlite` while the app is idle or use `.backup`.
