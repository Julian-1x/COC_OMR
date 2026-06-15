# Build a release APK with Supabase keys baked in from secrets.json
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$secrets = Join-Path $root "secrets.json"

if (-not (Test-Path $secrets)) {
    Write-Host "Missing secrets.json - copy secrets.json.example and fill in Supabase keys."
    exit 1
}

Set-Location $root
flutter build apk --release --dart-define-from-file=$secrets @args

Write-Host ""
Write-Host "APK: build\app\outputs\flutter-apk\app-release.apk"
