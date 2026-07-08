# COC OMR API

Laravel 11 + Sanctum backend for the COC OMR mobile app and web portal. Replaces Supabase for auth, sync, and teacher data.

## Requirements

- PHP 8.2+
- Composer 2.x
- SQLite (dev) or PostgreSQL (production)

## Quick start

```bash
cd coc-omr-api
composer install
cp .env.example .env
php artisan key:generate
touch database/database.sqlite   # skip if using PostgreSQL
php artisan migrate
php artisan serve
```

API base URL: `http://localhost:8000/api`

See [../laravel/SETUP.md](../laravel/SETUP.md) for school deployment notes.

## Authentication

All protected routes use `Authorization: Bearer {token}` (Sanctum personal access tokens).

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/register` | Create account + teacher profile |
| POST | `/api/login` | Issue token |
| POST | `/api/logout` | Revoke current token |
| GET | `/api/me` | Current user + profile |
| GET | `/api/email/verify/{id}/{hash}` | Verify email (signed URL) |
| POST | `/api/email/verification-notification` | Resend verification email |
| POST | `/api/forgot-password` | Send reset link |
| POST | `/api/reset-password` | Reset password |

**Register body**

```json
{
  "email": "teacher@school.edu",
  "password": "secret",
  "password_confirmation": "secret",
  "full_name": "Jane Teacher",
  "school": "COC High School"
}
```

**Email verification redirects**

- Mobile: `edu.coc.omr://login-callback?token=...&verified=1` (append `?platform=mobile` to verify link)
- Web: `{FRONTEND_URL}/auth/callback?token=...&verified=1` (default `?platform=web`)

Set `AUTO_VERIFY_EMAIL=true` in `.env` for local dev to skip verification.

## Mobile sync API

Matches `lib/services/cloud_sync_service.dart` behavior.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/sync/snapshot` | Pull cloud data (active sections only) |
| POST | `/api/sync/sections` | Upsert section (`owner_teacher_id,name`) |
| PATCH | `/api/sync/sections/archive` | Archive section by name |
| POST | `/api/sync/students` | Upsert student (`owner_teacher_id,school_id`) |
| POST | `/api/sync/subjects` | Upsert subject (`owner_teacher_id,local_id`) |
| POST | `/api/sync/scan-results` | Insert/update scan result |
| POST | `/api/sync/deadlines` | Upsert deadline (`owner_teacher_id,local_id`) |
| DELETE | `/api/sync/{table}/{id}` | Delete row (`sections`, `students`, `subjects`, `scan_results`, `deadlines`) |

## Profile & releases

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/profile/pin` | Fetch PIN hash/salt for offline unlock |
| PUT | `/api/profile/pin` | Save PIN hash/salt |
| GET | `/api/app-releases/latest` | Latest APK release metadata |

## Web portal API

CRUD for teachers; school admins get read-only access to same-school data.

| Resource | Paths |
|----------|-------|
| Sections | `/api/sections` |
| Students | `/api/students` |
| Subjects | `/api/subjects`, `/api/subjects/by-local/{localId}` |
| Scan results | `/api/scan-results` |
| Dashboard | `/api/dashboard/stats`, `/api/dashboard/last-updated` |
| Admin | `/api/admin/stats`, `/api/admin/teachers`, `/api/admin/teachers/{id}`, `/api/admin/teachers/{id}/sections/{name}/students` |

## Authorization

- Teachers: full CRUD on rows where `owner_teacher_id` = their user id.
- `school_admin` / `admin` role: read-only across teachers with the same `school_name` (see `supabase/add_admin_rls.sql`).

Promote an admin in the database:

```sql
UPDATE teacher_profiles SET role = 'school_admin' WHERE id = 'USER-UUID';
```

## CORS

Allowed origins: `FRONTEND_URL` from `.env`, optional comma-separated `CORS_EXTRA_ORIGINS`, plus `http://localhost:3000` for local dev (see `config/cors.php`).

Free cloud deploy: [../laravel/FREE_CLOUD.md](../laravel/FREE_CLOUD.md)

## Schema

Tables mirror `supabase/schema.sql` plus `app_releases`. JSON columns replace PostgreSQL `jsonb`.

## Publishing APK updates

```sql
INSERT INTO app_releases (build_number, version_name, download_url, notes, mandatory)
VALUES (2, '1.0.1', 'https://example.com/app-release.apk', 'Bug fixes', 0);
```
