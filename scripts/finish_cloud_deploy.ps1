# After Render deploy: set API URL on Vercel + secrets.json, then redeploy web.
param(
  [Parameter(Mandatory = $true)]
  [string]$ApiUrl,

  [string]$WebUrl = "https://omrweb.vercel.app"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$apiUrl = $ApiUrl.Trim().TrimEnd("/")
$webHost = ($WebUrl -replace '^https?://','').TrimEnd('/')

Write-Host "API: $apiUrl"
Write-Host "Web: $WebUrl"

& (Join-Path $PSScriptRoot "deploy_free_cloud.ps1") -ApiUrl $apiUrl -UpdateSecrets

Write-Host ""
Write-Host "Update Render env (coc-omr-api service):" -ForegroundColor Yellow
Write-Host "  FRONTEND_URL=$WebUrl"
Write-Host "  SANCTUM_STATEFUL_DOMAINS=$webHost,$(($apiUrl -replace '^https?://',''))"
Write-Host "  APP_URL=$apiUrl"
