# Easiest email fix: Brevo API key (skips SMTP entirely).

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== EASIEST FIX: Brevo API key (not SMTP) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "SMTP keeps failing on Render. Use the Brevo API instead."
Write-Host ""
Write-Host "STEP 1 - Brevo API key"
Write-Host "  1. Brevo -> Settings -> SMTP and API"
Write-Host "  2. Open the API KEYS tab (not SMTP keys)"
Write-Host "  3. Create a new API key -> copy it"
Write-Host ""
Write-Host "STEP 2 - Render"
Write-Host "  1. coc-omr-api -> Environment"
Write-Host "  2. Add: BREVO_API_KEY = (paste API key)"
Write-Host "  3. Keep: MAIL_FROM_ADDRESS = alex.balaba.coc@phinmaed.com"
Write-Host "  4. Keep: MAIL_FROM_NAME = COC OMR"
Write-Host "  5. Save -> Manual Deploy -> wait for Live"
Write-Host ""
Write-Host "STEP 3 - Test"
Write-Host "  omrweb.vercel.app/login -> Resend confirmation email"
Write-Host "  Brevo -> Transactional -> Logs should show 1 entry"
Write-Host ""

Start-Process "https://app.brevo.com/settings/keys/api"
Start-Sleep -Seconds 2
Start-Process "https://dashboard.render.com"

Write-Host "Opened Brevo API keys and Render." -ForegroundColor Green
