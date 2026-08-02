# COC OMR

Offline-first OMR scanner for Cagayan de Oro College — **production software** for real classroom use.

## Docs

| Guide | Who |
|-------|-----|
| [TEACHER_GUIDE.md](TEACHER_GUIDE.md) | Teachers |
| [SCAN_VALIDATION.md](SCAN_VALIDATION.md) | Before exam day (required per printer) |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Rollout and release gate |
| [RELEASE.md](RELEASE.md) | Building/installing APK |
| [PRODUCTION.md](PRODUCTION.md) | Laravel API, sync, operations |
| [PRIVACY.md](PRIVACY.md) | Data handling |
| [laravel/WINDOWS_SERVER.md](laravel/WINDOWS_SERVER.md) | **Production on Windows Server** (XAMPP + PostgreSQL) |
| [laravel/SELF_HOSTED.md](laravel/SELF_HOSTED.md) | Production on Linux (alternative) |
| [omr_web/README.md](omr_web/README.md) | Teacher web portal (desk companion) |

## Quick dev run

```powershell
copy secrets.json.example secrets.json
# Edit secrets.json — see laravel/SETUP.md

flutter pub get
.\scripts\run.ps1
```

Or in Cursor: **Run → OMR App - Laravel API** (uses `secrets.json` automatically).

## Tests

```bash
flutter analyze
flutter test
```
