# Opens Render and prints the exact mail env vars to paste.
# Secrets (MAIL_PASSWORD) must be pasted manually in the dashboard.

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== COC OMR - Render email setup (2 minutes) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "I cannot log into Render for you. Follow these steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. This script opens Render -> coc-omr-api -> Environment"
Write-Host "2. Add or fix ONLY the rows below (copy values exactly)"
Write-Host "3. Click Save Changes and wait until the service is Live"
Write-Host "4. Open Shell on Render and run:"
Write-Host "     php artisan mail:test ratateeth@gmail.com"
Write-Host "5. Refresh Brevo -> Transactional -> Logs (should show 1+ entry)"
Write-Host ""

$table = @(
  @{ Key = "MAIL_MAILER"; Value = "smtp" },
  @{ Key = "MAIL_HOST"; Value = "smtp-relay.brevo.com" },
  @{ Key = "MAIL_PORT"; Value = "587" },
  @{ Key = "MAIL_ENCRYPTION"; Value = "tls" },
  @{ Key = "MAIL_USERNAME"; Value = "b160f1001@smtp-brevo.com" },
  @{ Key = "MAIL_PASSWORD"; Value = "paste your Brevo SMTP key (not API key)" },
  @{ Key = "MAIL_FROM_ADDRESS"; Value = "alex.balaba.coc@phinmaed.com" },
  @{ Key = "MAIL_FROM_NAME"; Value = "COC OMR" },
  @{ Key = "AUTO_VERIFY_EMAIL"; Value = "false" }
)

$table | Format-Table -AutoSize

Write-Host "Opening Render dashboard..." -ForegroundColor Green
Start-Process "https://dashboard.render.com"

Write-Host ""
Write-Host "After mail works, resend confirmation from the web login page." -ForegroundColor Cyan
Write-Host ""
