# One-shot: campus production + public HTTPS tunnels + firewall
# Run in PowerShell (Admin recommended for firewall rules).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "=== COC OMR public setup ===" -ForegroundColor Cyan

# 1. Campus stack
Write-Host "`n[1/4] Starting campus production (Apache + web)..."
& "$root\scripts\start_production.ps1"

# 2. Firewall for permanent public (DuckDNS path)
Write-Host "`n[2/4] Opening Windows firewall for HTTP/HTTPS..."
foreach ($port in @(80, 443)) {
    $name = "COC OMR port $port"
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        Write-Host "  Added rule: $name"
    } else {
        Write-Host "  Rule exists: $name"
    }
}

# 3. DuckDNS token placeholder
Write-Host "`n[3/4] DuckDNS (permanent DNS)..."
& "$root\scripts\update_duckdns.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  (Skip until you add duckdns.token — see D:\coc-omr\duckdns.token)"
}

# 4. Cloudflare tunnels (works immediately)
Write-Host "`n[4/4] Starting public HTTPS tunnels..."
& "$root\scripts\start_public_tunnels.ps1"

Write-Host "`n=== Done ===" -ForegroundColor Green
Get-Content "D:\coc-omr\PUBLIC_URLS.md" -ErrorAction SilentlyContinue
