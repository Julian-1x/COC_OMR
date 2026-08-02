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

Write-Host "Building omr_web..."
Push-Location $web
try {
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }

  $vercel = "npx"
  $vercelArgs = @("vercel@latest")

  function Set-VercelEnv([string]$name, [string]$value) {
    Write-Host "Setting Vercel env: $name (production)"
    # npx may write warnings to stderr; do not treat that as a hard failure.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $value | & $vercel @vercelArgs env add $name production --force 2>$null
      if ($LASTEXITCODE -ne 0) {
        $value | & $vercel @vercelArgs env add $name production
      }
    } finally {
      $ErrorActionPreference = $prev
    }
  }

  # Env vars are usually already set on Vercel; skip if update fails.
  try {
    Set-VercelEnv "API_BASE_URL" $apiUrl
    Set-VercelEnv "NEXT_PUBLIC_API_BASE_URL" $apiUrl
  } catch {
    Write-Warning "Could not update Vercel env vars (continuing deploy): $_"
  }

  Write-Host "Deploying to Vercel (production)..."
  $ErrorActionPreference = "Continue"
  & $vercel @vercelArgs deploy --prod --yes
  if ($LASTEXITCODE -ne 0) { throw "vercel deploy failed" }
  $ErrorActionPreference = "Stop"

  Write-Host ""
  Write-Host "Done. Set FRONTEND_URL on the Laravel API to your Vercel URL so email verification redirects work:"
  Write-Host "  https://YOUR-VERCEL-URL/auth/callback"
}
finally {
  Pop-Location
}
