@echo off
cd /d "%~dp0.."
if not exist secrets.json (
  echo Missing secrets.json - copy secrets.json.example and add your Supabase keys.
  exit /b 1
)
flutter build apk --release --dart-define-from-file=secrets.json %*
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
