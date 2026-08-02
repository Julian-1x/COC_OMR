# Deploy COC OMR to D:\coc-omr on this Windows Server.
# Re-run after pulling app updates from git.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$php = "D:\xampp\php\php.exe"
$composer = "D:\dev\composer.phar"

New-Item -ItemType Directory -Force -Path D:\coc-omr\api, D:\coc-omr\web, D:\coc-omr\downloads, D:\coc-omr\backups | Out-Null

Write-Host "Copying API and web..."
robocopy "$root\coc-omr-api" D:\coc-omr\api /E /XD vendor node_modules .git /NFL /NDL /NJH /NJS /nc /ns /np
robocopy "$root\omr_web" D:\coc-omr\web /E /XD node_modules .next .git /NFL /NDL /NJH /NJS /nc /ns /np

Write-Host "Composer install (API)..."
Push-Location D:\coc-omr\api
& $php $composer install --no-dev --optimize-autoloader --no-interaction
if (-not (Test-Path database\database.sqlite)) { New-Item database\database.sqlite -ItemType File | Out-Null }
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
& $php artisan key:generate --force
& $php artisan migrate --force
Pop-Location

Write-Host "npm build (web)..."
Push-Location D:\coc-omr\web
if (-not (Test-Path .env.production)) {
@'
API_BASE_URL=http://phinma-coc-omr.omr
NEXT_PUBLIC_API_BASE_URL=http://phinma-coc-omr.omr
'@ | Set-Content .env.production
}
npm ci
npm run build
Pop-Location

Write-Host ""
Write-Host "Deploy files updated. Run:"
Write-Host "  .\scripts\setup_coc_hosts.ps1   (Admin, once)"
Write-Host "  .\scripts\start_production.ps1"
