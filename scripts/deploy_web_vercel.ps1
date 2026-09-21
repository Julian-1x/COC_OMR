# Deploy COC OMR teacher web portal to Vercel (production).
# Prereq: run once from omr_web — npx vercel@latest login
# Usage: .\scripts\deploy_web_vercel.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$web = Join-Path $root "omr_web"
$secretsPath = Join-Path $root "secrets.json"

if (-not (Test-Path $web)) {
  throw "omr_web folder not found at $web"
}

function Read-Secrets {
  if (Test-Path $secretsPath) {
    return Get-Content $secretsPath -Raw | ConvertFrom-Json
  }
  $envLocal = Join-Path $web ".env.local"
  if (-not (Test-Path $envLocal)) {
    throw "Missing secrets.json and omr_web/.env.local"
  }
  $lines = Get-Content $envLocal | Where-Object { $_ -match "=" -and $_ -notmatch "^\s*#" }
  $map = @{}
  foreach ($line in $lines) {
    $parts = $line.Split("=", 2)
    $map[$parts[0].Trim()] = $parts[1].Trim()
  }
  return [pscustomobject]@{
    API_BASE_URL = $map["API_BASE_URL"]
  }
}

$secrets = Read-Secrets
$apiUrl = $secrets.API_BASE_URL
if (-not $apiUrl) {
  throw "API_BASE_URL is required in secrets.json or omr_web/.env.local"
}

# Project Root Directory on Vercel is `omr_web`. Deploy from the monorepo root
# so that folder exists in the upload (deploying from inside omr_web fails).
# .vercelignore keeps the upload small (omr_web only).
$vercelDir = Join-Path $root ".vercel"
$webVercel = Join-Path $web ".vercel\project.json"
if (-not (Test-Path $webVercel)) {
  throw "Missing omr_web\.vercel\project.json — run: cd omr_web; npx vercel link"
}
New-Item -ItemType Directory -Force $vercelDir | Out-Null
Copy-Item -Force $webVercel (Join-Path $vercelDir "project.json")

Write-Host "Deploying omr_web to Vercel (production) from monorepo root..."
Push-Location $root
try {
  $ErrorActionPreference = "Continue"
  & npx vercel@latest deploy --prod --yes
  if ($LASTEXITCODE -ne 0) { throw "vercel deploy failed" }
  $ErrorActionPreference = "Stop"

  Write-Host ""
  Write-Host "Done. Portal: https://omrweb.vercel.app"
  Write-Host "Confirm API_BASE_URL / NEXT_PUBLIC_API_BASE_URL on Vercel still point at:"
  Write-Host "  $apiUrl"
}
finally {
  Pop-Location
}
