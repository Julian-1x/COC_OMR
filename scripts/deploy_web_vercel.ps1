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
    SUPABASE_URL = $map["SUPABASE_URL"]
    SUPABASE_PUBLISHABLE_KEY = $map["SUPABASE_PUBLISHABLE_KEY"]
  }
}

$secrets = Read-Secrets
$url = $secrets.SUPABASE_URL
$key = $secrets.SUPABASE_PUBLISHABLE_KEY
if (-not $url -or -not $key) {
  throw "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required."
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
    $value | & $vercel @vercelArgs env add $name production --force 2>$null
    if ($LASTEXITCODE -ne 0) {
      $value | & $vercel @vercelArgs env add $name production
    }
  }

  Set-VercelEnv "SUPABASE_URL" $url
  Set-VercelEnv "SUPABASE_PUBLISHABLE_KEY" $key
  Set-VercelEnv "NEXT_PUBLIC_SUPABASE_URL" $url
  Set-VercelEnv "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY" $key

  Write-Host "Deploying to Vercel (production)..."
  & $vercel @vercelArgs deploy --prod --yes
  if ($LASTEXITCODE -ne 0) { throw "vercel deploy failed" }

  Write-Host ""
  Write-Host "Done. Add this redirect URL in Supabase -> Authentication -> URL Configuration:"
  Write-Host "  https://YOUR-VERCEL-URL/auth/callback"
}
finally {
  Pop-Location
}
