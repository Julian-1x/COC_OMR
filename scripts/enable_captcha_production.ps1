# Enable Cloudflare Turnstile CAPTCHA on production (Render + Vercel).
# Prereq: Create a Turnstile widget at https://dash.cloudflare.com/?to=/:account/turnstile
#   Hostnames: omrweb.vercel.app , localhost
#
# Usage:
#   .\scripts\enable_captcha_production.ps1 -SiteKey "0x..." -SecretKey "0x..."
# Or run without params to be prompted.

param(
  [string]$SiteKey,
  [string]$SecretKey,
  [switch]$SkipVercelDeploy
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$web = Join-Path $root "omr_web"
$envLocal = Join-Path $web ".env.local"
$apiUrl = "https://coc-omr-api.onrender.com"
$webUrl = "https://omrweb.vercel.app"

Write-Host ""
Write-Host "=== COC OMR - enable CAPTCHA (Cloudflare Turnstile) ===" -ForegroundColor Cyan
Write-Host ""

if (-not $SiteKey) {
  Write-Host "Get keys: Cloudflare dashboard -> Turnstile -> Add widget" -ForegroundColor Yellow
  Write-Host "  Widget mode: Managed"
  Write-Host "  Domains: omrweb.vercel.app , localhost"
  Write-Host ""
  Start-Process "https://dash.cloudflare.com/?to=/:account/turnstile"
  $SiteKey = Read-Host "Paste SITE key (public)"
}
if (-not $SecretKey) {
  $SecretKey = Read-Host "Paste SECRET key"
}

$SiteKey = $SiteKey.Trim()
$SecretKey = $SecretKey.Trim()
if ($SiteKey.Length -lt 10 -or $SecretKey.Length -lt 10) {
  throw "Site key and secret key look too short. Copy both from Cloudflare Turnstile."
}

Write-Host ""
Write-Host "Step 1: Updating omr_web/.env.local ..." -ForegroundColor Green
$lines = @()
if (Test-Path $envLocal) {
  $lines = Get-Content $envLocal
}
$lines = $lines | Where-Object {
  $_ -notmatch '^\s*NEXT_PUBLIC_CAPTCHA_SITE_KEY\s*='
}
$lines += "NEXT_PUBLIC_CAPTCHA_SITE_KEY=$SiteKey"
Set-Content -Path $envLocal -Value $lines -Encoding UTF8

if (-not $SkipVercelDeploy) {
  Write-Host "Step 2: Setting Vercel production env + redeploying web ..." -ForegroundColor Green
  $vercelArgs = @("vercel@latest")
  Push-Location $web
  try {
    $SiteKey | npx @vercelArgs env add NEXT_PUBLIC_CAPTCHA_SITE_KEY production --force 2>$null
    if ($LASTEXITCODE -ne 0) {
      $SiteKey | npx @vercelArgs env add NEXT_PUBLIC_CAPTCHA_SITE_KEY production
    }
    npx @vercelArgs deploy --prod --yes
    if ($LASTEXITCODE -ne 0) { throw "Vercel deploy failed" }
  } finally {
    Pop-Location
  }
} else {
  Write-Host "Step 2: Skipped Vercel deploy (-SkipVercelDeploy)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 3: Render API - paste these in coc-omr-api Environment, then Save:" -ForegroundColor Yellow
Write-Host ""
@(
  @{ Key = "CAPTCHA_ENABLED"; Value = "true" },
  @{ Key = "CAPTCHA_SITE_KEY"; Value = $SiteKey },
  @{ Key = "CAPTCHA_SECRET_KEY"; Value = $SecretKey }
) | Format-Table -AutoSize

Write-Host "After Save, wait until Render shows Live." -ForegroundColor Cyan
Start-Process "https://dashboard.render.com"

Write-Host ""
Write-Host "Step 4: Waiting for API to report captcha_enabled=true ..." -ForegroundColor Green
$deadline = (Get-Date).AddMinutes(10)
$live = $false
while ((Get-Date) -lt $deadline) {
  try {
    $cfg = Invoke-RestMethod -Uri "$apiUrl/api/auth/security-config" -TimeoutSec 90
    if ($cfg.captcha_enabled -eq $true) {
      Write-Host "CAPTCHA is LIVE on the API." -ForegroundColor Green
      $cfg | ConvertTo-Json -Compress
      $live = $true
      break
    }
  } catch {
    # Render may still be redeploying
  }
  Write-Host "$(Get-Date -Format 'HH:mm:ss') waiting for Render redeploy..."
  Start-Sleep -Seconds 20
}

if (-not $live) {
  Write-Host ""
  Write-Host "API not showing captcha yet. After you save Render env vars, verify:" -ForegroundColor Yellow
  Write-Host "  $apiUrl/api/auth/security-config"
}

Write-Host ""
Write-Host "Step 5: Build new APK (mobile Turnstile support):" -ForegroundColor Green
Write-Host "  .\scripts\build_release.ps1"
Write-Host ""
Write-Host "Smoke test:" -ForegroundColor Cyan
Write-Host "  - $webUrl/login (register tab should show Turnstile)"
Write-Host "  - Forgot password on web + phone after new APK"
