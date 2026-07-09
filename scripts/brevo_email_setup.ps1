# Brevo email fix - regenerates SMTP key and opens the right pages.
# You still paste the new key into Render yourself (I cannot log in for you).

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Brevo fix (most common mistake) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Problem: 0 logs in Brevo usually means the SMTP KEY in Render is wrong."
Write-Host "Fix: create a NEW SMTP key in Brevo and paste ONLY that into Render."
Write-Host ""
Write-Host "STEP 1 - Brevo SMTP key (opens in browser)"
Write-Host "  1. Click 'Generate a new SMTP key' (or create new key)"
Write-Host "  2. Name it: COC OMR Render"
Write-Host "  3. COPY the key immediately (shown once)"
Write-Host ""
Write-Host "STEP 2 - Render (second browser tab)"
Write-Host "  1. coc-omr-api -> Environment"
Write-Host "  2. MAIL_PASSWORD = paste the NEW key from step 1"
Write-Host "  3. Confirm these are also set:"
Write-Host "       MAIL_MAILER = smtp"
Write-Host "       MAIL_USERNAME = b160f1001@smtp-brevo.com"
Write-Host "       MAIL_FROM_ADDRESS = alex.balaba.coc@phinmaed.com"
Write-Host "  4. Save Changes -> wait until Live"
Write-Host ""
Write-Host "STEP 3 - Test on Render Shell"
Write-Host "  php artisan mail:test ratateeth@gmail.com"
Write-Host ""
Write-Host "STEP 4 - Check Brevo -> Transactional -> Logs (should NOT be 0 anymore)"
Write-Host ""
Write-Host "DO NOT use:"
Write-Host "  - Brevo API key (wrong place)"
Write-Host "  - Your Brevo login password"
Write-Host "  - b160f1001@smtp-brevo.com as MAIL_FROM (only as MAIL_USERNAME)"
Write-Host ""

Start-Process "https://app.brevo.com/settings/keys/smtp"
Start-Sleep -Seconds 2
Start-Process "https://dashboard.render.com"

Write-Host "Opened Brevo SMTP page and Render dashboard." -ForegroundColor Green
Write-Host ""
