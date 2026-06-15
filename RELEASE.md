# Building a release APK

App ID: **edu.coc.omr**  
Display name: **COC OMR**

## One-time: create signing key

```powershell
cd d:\omr_app
.\scripts\create_release_keystore.ps1
```

Then:

1. Copy `android/key.properties.example` → `android/key.properties`
2. Fill in passwords (same ones you chose for the keystore)

## Configure keys once

```powershell
copy secrets.json.example secrets.json
# Edit secrets.json with your Supabase URL and publishable key
```

See [supabase/SETUP.md](supabase/SETUP.md) for full Supabase project setup.

## Build release APK

```powershell
.\scripts\build_release.ps1
```

Or manually:

```bash
flutter build apk --release --dart-define-from-file=secrets.json
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

`SENTRY_DSN` is optional — set `SENTRY_ENVIRONMENT` to `production` when enabled.

**Production:** configure `android/key.properties` and sign with the release keystore. Debug-signed APKs are for development only.

## Install on teacher phones

- Share the APK (Google Drive, USB, or MDM)
- Enable “Install unknown apps” for the file manager they use
- Teachers uninstall old `com.example` builds before installing

## iOS (TestFlight)

1. Apple Developer account required
2. Set bundle ID `edu.coc.omr` in Xcode
3. `cd ios && pod install`
4. Archive in Xcode → distribute via TestFlight

See also [PRODUCTION.md](PRODUCTION.md), [DEPLOYMENT.md](DEPLOYMENT.md), and [TEACHER_GUIDE.md](TEACHER_GUIDE.md).
