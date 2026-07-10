# Opens DBeaver and prints how to connect to Render PostgreSQL (coc-omr-db).
# You must copy the External Database URL from Render yourself (secret).

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "COC OMR - connect DBeaver to Render PostgreSQL" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Open https://dashboard.render.com"
Write-Host "2. Click your database: coc-omr-db"
Write-Host "3. Copy External Database URL (postgresql://...)"
Write-Host ""
Write-Host "4. In DBeaver: Database -> New Database Connection -> PostgreSQL"
Write-Host "5. Main tab - fill from the URL:"
Write-Host "   Host, Port, Database=coc_omr, Username, Password"
Write-Host "6. SSL tab - SSL mode: require"
Write-Host "7. Test Connection -> Finish"
Write-Host ""
Write-Host "8. Open SQL script:" -ForegroundColor Green
Write-Host "   $PSScriptRoot\render_db_queries.sql"
Write-Host ""

$dbeaverPaths = @(
  "$env:LocalAppData\DBeaver\dbeaver.exe",
  "$env:ProgramFiles\DBeaver\dbeaver.exe",
  "$env:ProgramFiles\dbeaver\dbeaver.exe"
)

$exe = $dbeaverPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($exe) {
  Write-Host "Launching DBeaver..." -ForegroundColor Green
  Start-Process -FilePath $exe
} else {
  Write-Host "DBeaver not found. Run: winget install DBeaver.DBeaver.Community" -ForegroundColor Yellow
}
