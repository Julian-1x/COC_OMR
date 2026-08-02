# Start COC OMR production — http://phinma-coc-omr.omr

$ErrorActionPreference = "Stop"
$api = "D:\coc-omr\api"
$web = "D:\coc-omr\web"
$php = "D:\xampp\php\php.exe"
$apache = "D:\xampp\apache\bin\httpd.exe"
$baseUrl = "http://phinma-coc-omr.omr"
$hostHeader = "phinma-coc-omr.omr"

Write-Host "COC OMR"
Write-Host "  http://phinma-coc-omr.omr/login"
Write-Host "  http://192.168.254.101/login  (phones on Wi-Fi, no DNS yet)"
Write-Host ""

$hosts = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -Raw
if ($hosts -notmatch "phinma-coc-omr\.omr") {
  Write-Host "TIP: Run as Admin: PowerShell -ExecutionPolicy Bypass -File .\scripts\setup_coc_hosts.ps1"
  Write-Host ""
}

# Firewall — allow phones on Wi-Fi (needs Admin)
foreach ($port in @(80)) {
  $name = "COC OMR HTTP"
  try {
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction Stop | Out-Null
    }
  } catch {
    Write-Host "TIP: Run as Admin once to open firewall port 80 for phones on Wi-Fi."
  }
}

Get-Process httpd -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
Start-Process -FilePath $apache -WindowStyle Hidden
Start-Sleep 2

Get-CimInstance Win32_Process -Filter "Name='php.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match "artisan serve" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process -FilePath $php -ArgumentList "artisan","serve","--host=127.0.0.1","--port=8080" `
  -WorkingDirectory $api -WindowStyle Hidden
Start-Sleep 2

Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
Start-Sleep 2

Push-Location $web
if (-not (Test-Path .next\BUILD_ID)) {
  Write-Host "Building web portal..."
  npm run build 2>&1 | Out-Null
}
Pop-Location

$env:API_BASE_URL = $baseUrl
$env:NEXT_PUBLIC_API_BASE_URL = $baseUrl
Start-Process -FilePath "npm.cmd" -ArgumentList "start" -WorkingDirectory $web -WindowStyle Hidden
Start-Sleep -Seconds 5

try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1/up" -Headers @{Host=$hostHeader} -UseBasicParsing -TimeoutSec 10
  Write-Host "API: OK ($($r.StatusCode))"
  $w = Invoke-WebRequest -Uri "http://127.0.0.1/login" -Headers @{Host=$hostHeader} -UseBasicParsing -TimeoutSec 10
  Write-Host "Web: OK ($($w.StatusCode))"
} catch {
  Write-Host "Check failed: $_"
}

Write-Host ""
Write-Host "Ready."
