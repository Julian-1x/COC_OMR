# Keep the school Laravel API awake during exam week (free hosts often sleep).
# Usage:
#   .\scripts\keep_api_awake.ps1
#   .\scripts\keep_api_awake.ps1 -ApiBaseUrl https://your-api.example.com -IntervalSeconds 600
#
# Stop with Ctrl+C. Prefer an always-on host for production exam days.

param(
  [string]$ApiBaseUrl = $env:API_BASE_URL,
  [int]$IntervalSeconds = 600
)

$ErrorActionPreference = "Stop"

if (-not $ApiBaseUrl -or $ApiBaseUrl.Trim().Length -eq 0) {
  $ApiBaseUrl = "https://coc-omr-api-sg.onrender.com"
}

$base = $ApiBaseUrl.TrimEnd("/")
$up = "$base/up"

Write-Host "COC OMR API keep-awake" -ForegroundColor Cyan
Write-Host "Pinging $up every $IntervalSeconds seconds. Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

while ($true) {
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  try {
    $response = Invoke-WebRequest -Uri $up -Method GET -TimeoutSec 30 -UseBasicParsing
    Write-Host "[$stamp] OK $($response.StatusCode)" -ForegroundColor Green
  } catch {
    Write-Host "[$stamp] FAIL $($_.Exception.Message)" -ForegroundColor Red
  }
  Start-Sleep -Seconds $IntervalSeconds
}
