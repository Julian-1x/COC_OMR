# Add phinma-coc-omr.omr to Windows hosts (Admin PowerShell).

$ErrorActionPreference = "Stop"
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostname = "phinma-coc-omr.omr"

$lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
  $_.IPAddress -notmatch "^127\." -and $_.PrefixOrigin -ne "WellKnown"
} | Select-Object -First 1).IPAddress
$ip = if ($lan) { $lan } else { "127.0.0.1" }
Write-Host "Server IP: $ip"

$content = Get-Content $hostsPath -Raw
if ($content -match [regex]::Escape($hostname)) {
  Write-Host "Already in hosts: $hostname"
} else {
  Add-Content -Path $hostsPath -Value "`n# COC OMR`n$ip`t$hostname" -Encoding ASCII
  Write-Host "Added: $ip -> $hostname"
}

# Remove old names if present
$lines = Get-Content $hostsPath | Where-Object {
  $_ -notmatch "omr\.coc" -and $_ -notmatch "duckdns"
}
$lines | Set-Content $hostsPath -Encoding ASCII
Write-Host "Cleaned old omr.coc / duckdns hosts entries."

Write-Host ""
Write-Host "=== URLs ==="
Write-Host "  PC browser:  http://phinma-coc-omr.omr/login"
Write-Host "  Phone (DNS): http://phinma-coc-omr.omr/login"
Write-Host "  Phone (LAN): http://192.168.254.101/login  (until school DNS is set)"
Write-Host ""
Write-Host "School IT: DNS A record  phinma-coc-omr.omr -> $ip"
