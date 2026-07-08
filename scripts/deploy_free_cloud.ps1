# Deploy COC OMR to free cloud: Vercel (web) + your Laravel API URL.
# Prereq: API already live at https://... (Oracle VM or Render). See laravel/FREE_CLOUD.md
#
# Usage:
#   .\scripts\deploy_free_cloud.ps1 -ApiUrl "https://api.example.com"
#   .\scripts\deploy_free_cloud.ps1 -ApiUrl "https://api.example.com" -SkipVercel
#   .\scripts\deploy_free_cloud.ps1 -ApiUrl "https://api.example.com" -UpdateSecrets

param(
  [Parameter(Mandatory = $true)]
  [string]$ApiUrl,

  [switch]$SkipVercel,
  [switch]$UpdateSecrets
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$secretsPath = Join-Path $root "secrets.json"
$apiUrl = $ApiUrl.Trim().TrimEnd("/")

if ($apiUrl -notmatch "^https://") {
  Write-Warning "Production phones need HTTPS. Use https:// for API_BASE_URL."
}

Write-Host "=== COC OMR free cloud deploy ===" -ForegroundColor Cyan
Write-Host "API: $apiUrl"

if ($UpdateSecrets -or -not (Test-Path $secretsPath)) {
  $secrets = @{
    API_BASE_URL         = $apiUrl
    SENTRY_DSN           = ""
    SENTRY_ENVIRONMENT   = "production"
  }
  if (Test-Path $secretsPath) {
    $existing = Get-Content $secretsPath -Raw | ConvertFrom-Json
    if ($existing.SENTRY_DSN) { $secrets.SENTRY_DSN = $existing.SENTRY_DSN }
  }
  $secrets | ConvertTo-Json | Set-Content -Path $secretsPath -Encoding UTF8
  Write-Host "Updated secrets.json (API_BASE_URL=$apiUrl)"
}

Write-Host ""
Write-Host "Set on Laravel server (.env):" -ForegroundColor Yellow
Write-Host "  APP_URL=$apiUrl"
Write-Host "  FRONTEND_URL=https://YOUR-APP.vercel.app"
Write-Host "  SANCTUM_STATEFUL_DOMAINS=YOUR-APP.vercel.app,$(($apiUrl -replace '^https?://',''))"
Write-Host "  AUTO_VERIFY_EMAIL=false"
Write-Host "  php artisan config:cache"
Write-Host ""

if (-not $SkipVercel) {
  $webScript = Join-Path $PSScriptRoot "deploy_web_vercel.ps1"
  if (-not (Test-Path $webScript)) {
    throw "Missing $webScript"
  }

  # deploy_web_vercel reads secrets.json for API_BASE_URL
  & $webScript
  if ($LASTEXITCODE -ne 0) { throw "Vercel deploy failed" }

  Write-Host ""
  Write-Host "Next:" -ForegroundColor Green
  Write-Host "  1. Copy your Vercel URL into Laravel FRONTEND_URL + SANCTUM_STATEFUL_DOMAINS"
  Write-Host "  2. .\scripts\build_release.ps1"
  Write-Host "  3. Smoke test: laravel/FREE_CLOUD.md step 5"
} else {
  Write-Host "Skipped Vercel. Run .\scripts\deploy_web_vercel.ps1 when ready."
}
