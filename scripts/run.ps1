# Run the app on a connected device/emulator with keys from secrets.json
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$secrets = Join-Path $root "secrets.json"

if (-not (Test-Path $secrets)) {
    Write-Host "Missing secrets.json"
    Write-Host "  1. Copy secrets.json.example to secrets.json"
    Write-Host "  2. Set API_BASE_URL to your Laravel school server"
    exit 1
}

Set-Location $root
flutter run --dart-define-from-file=$secrets @args
