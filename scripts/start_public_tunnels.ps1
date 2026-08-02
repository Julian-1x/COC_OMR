# HTTPS tunnels for immediate public access (no router config).
# Keeps running while this PC is on. URLs change if you restart tunnels.

$ErrorActionPreference = "Stop"
$cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
$logWeb = "D:\coc-omr\logs\tunnel-web.log"
$logApi = "D:\coc-omr\logs\tunnel-api.log"
New-Item -ItemType Directory -Force -Path D:\coc-omr\logs | Out-Null

# Stop old tunnels
Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "tunnel --url" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# API on 8080 (separate from Apache vhosts)
$php = "D:\xampp\php\php.exe"
Get-CimInstance Win32_Process -Filter "Name='php.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "artisan serve.*8080" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Process -FilePath $php -ArgumentList "artisan","serve","--host=127.0.0.1","--port=8080" `
    -WorkingDirectory "D:\coc-omr\api" -WindowStyle Hidden

Start-Sleep -Seconds 2

Start-Process -FilePath $cloudflared -ArgumentList "tunnel","--url","http://127.0.0.1:3000" `
    -RedirectStandardOutput $logWeb -RedirectStandardError "${logWeb}.err" -WindowStyle Hidden

Start-Process -FilePath $cloudflared -ArgumentList "tunnel","--url","http://127.0.0.1:8080" `
    -RedirectStandardOutput $logApi -RedirectStandardError "${logApi}.err" -WindowStyle Hidden

Write-Host "Waiting for tunnel URLs..."
$webUrl = $null
$apiUrl = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    if (-not $webUrl -and (Test-Path $logWeb)) {
        $wlog = (Get-Content $logWeb -Raw -ErrorAction SilentlyContinue) + (Get-Content "${logWeb}.err" -Raw -ErrorAction SilentlyContinue)
        if ($wlog -match "(https://[a-z0-9-]+\.trycloudflare\.com)") { $webUrl = $Matches[1] }
    }
    if (-not $apiUrl -and (Test-Path $logApi)) {
        $alog = (Get-Content $logApi -Raw -ErrorAction SilentlyContinue) + (Get-Content "${logApi}.err" -Raw -ErrorAction SilentlyContinue)
        if ($alog -match "(https://[a-z0-9-]+\.trycloudflare\.com)") { $apiUrl = $Matches[1] }
    }
    if ($webUrl -and $apiUrl) { break }
}

if (-not $webUrl -or -not $apiUrl) {
    Write-Host "Could not read tunnel URLs yet. Check:"
    Write-Host "  $logWeb"
    Write-Host "  $logApi"
    exit 1
}

Write-Host ""
Write-Host "PUBLIC WEB (HTTPS, anywhere): $webUrl"
Write-Host "PUBLIC API (HTTPS, anywhere): $apiUrl"

# Update deployed web env and rebuild
$apiNoSlash = $apiUrl.TrimEnd("/")
$webEnv = @"
API_BASE_URL=$apiNoSlash
NEXT_PUBLIC_API_BASE_URL=$apiNoSlash
"@
$webEnv | Set-Content "D:\coc-omr\web\.env.production" -Encoding UTF8

Push-Location D:\coc-omr\web
npm run build 2>&1 | Out-Null
Pop-Location

# Restart Next.js with new API URL
Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$env:API_BASE_URL = $apiNoSlash
$env:NEXT_PUBLIC_API_BASE_URL = $apiNoSlash
Start-Process -FilePath "npm.cmd" -ArgumentList "start" -WorkingDirectory "D:\coc-omr\web" -WindowStyle Hidden

# Update Laravel for tunnel web callback
$apiEnvPath = "D:\coc-omr\api\.env"
(Get-Content $apiEnvPath) `
    -replace '^APP_URL=.*', "APP_URL=$apiNoSlash" `
    -replace '^FRONTEND_URL=.*', "FRONTEND_URL=$($webUrl.TrimEnd('/'))" |
    Set-Content $apiEnvPath

# Mobile build config in repo
@{
    API_BASE_URL = $apiNoSlash
    SENTRY_DSN = ""
    SENTRY_ENVIRONMENT = "production"
} | ConvertTo-Json | Set-Content "d:\omr_app\secrets.json" -Encoding UTF8

# Save summary
@"
# COC OMR public URLs (generated $(Get-Date -Format 'yyyy-MM-dd HH:mm'))

## Use these NOW (phones on LTE, any Wi-Fi)

| Service | URL |
|---------|-----|
| Web portal | $webUrl |
| API | $apiNoSlash |

Open **$webUrl/login** on your phone.

APK build uses API: ``$apiNoSlash`` (in secrets.json).

## Permanent (after DuckDNS + router port forward)

| Service | URL |
|---------|-----|
| Web | http://cocomr.duckdns.org |
| API | http://cocomrapi.duckdns.org |

Your public IP: check https://api.ipify.org — forward ports 80 and 443 to 192.168.254.101

Run ``.\scripts\update_duckdns.ps1`` after adding token to ``D:\coc-omr\duckdns.token``.

## Campus LAN (still works)

| Web | http://omr.coc |
| API | http://api.omr.coc |
"@ | Set-Content "D:\coc-omr\PUBLIC_URLS.md" -Encoding UTF8

Write-Host ""
Write-Host "Saved D:\coc-omr\PUBLIC_URLS.md"
Write-Host "Open on your phone: $webUrl/login"
