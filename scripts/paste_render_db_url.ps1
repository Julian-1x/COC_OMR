# Paste your Render External Database URL locally (not in chat).
# Parses postgresql://... and prints DBeaver fields. Optional: test with psql.

param(
  [string]$DatabaseUrl
)

function Parse-PostgresUrl {
  param([string]$Url)

  $trimmed = $Url.Trim()
  if ($trimmed -match '^postgres(ql)?://') {
    $uri = [Uri]$trimmed
  } else {
    throw "URL must start with postgresql://"
  }

  $userInfo = $uri.UserInfo
  if ($userInfo -notmatch ':') {
    throw "URL must include user:password (copy the full External URL from Render)."
  }

  $userParts = $userInfo -split ':', 2
  $username = [Uri]::UnescapeDataString($userParts[0])
  $password = [Uri]::UnescapeDataString($userParts[1])
  $dbHost = $uri.Host
  $port = if ($uri.Port -gt 0) { $uri.Port } else { 5432 }
  $database = $uri.AbsolutePath.TrimStart('/')
  if ($database -eq '') {
    $database = 'coc_omr'
  }

  return [PSCustomObject]@{
    Host     = $dbHost
    Port     = $port
    Database = $database
    Username = $username
    Password = $password
  }
}

Write-Host ""
Write-Host "COC OMR - Render database URL helper" -ForegroundColor Cyan
Write-Host ""

if (-not $DatabaseUrl) {
  Write-Host "Paste your External Database URL from Render (postgresql://...)" -ForegroundColor Yellow
  Write-Host "Tip: dashboard.render.com -> coc-omr-db -> Connections -> External" -ForegroundColor DarkGray
  Write-Host ""
  $DatabaseUrl = Read-Host "Database URL"
}

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  Write-Host "No URL entered. Exiting." -ForegroundColor Red
  exit 1
}

try {
  $parsed = Parse-PostgresUrl -Url $DatabaseUrl
} catch {
  Write-Host "Could not parse URL: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "Use these in DBeaver (PostgreSQL connection):" -ForegroundColor Green
Write-Host "  Host:     $($parsed.Host)"
Write-Host "  Port:     $($parsed.Port)"
Write-Host "  Database: $($parsed.Database)"
Write-Host "  Username: $($parsed.Username)"
Write-Host "  Password: (shown below - copy into DBeaver Password field)"
Write-Host "  $($parsed.Password)"
Write-Host ""
Write-Host "SSL tab -> SSL mode: require" -ForegroundColor Green
Write-Host ""

$launch = Read-Host "Open DBeaver now? (y/n)"
if ($launch -eq 'y' -or $launch -eq 'Y') {
  $dbeaver = "$env:LocalAppData\DBeaver\dbeaver.exe"
  if (Test-Path $dbeaver) {
    Start-Process $dbeaver
  } else {
    Write-Host "DBeaver not found at $dbeaver" -ForegroundColor Yellow
  }
}

$runQuery = Read-Host "Try listing accounts with psql? (y/n) - needs PostgreSQL client installed"
if ($runQuery -eq 'y' -or $runQuery -eq 'Y') {
  $psql = Get-Command psql -ErrorAction SilentlyContinue
  if (-not $psql) {
    Write-Host "psql not installed. Use DBeaver -> open scripts\render_db_queries.sql instead." -ForegroundColor Yellow
    exit 0
  }

  $env:PGPASSWORD = $parsed.Password
  $query = @"
SELECT u.email, tp.full_name, tp.school_name, u.email_verified_at
FROM users u
LEFT JOIN teacher_profiles tp ON tp.id = u.id
ORDER BY u.created_at DESC;
"@

  & psql -h $parsed.Host -p $parsed.Port -U $parsed.Username -d $parsed.Database -c $query
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. Do not share your database URL in chat or commit it to git." -ForegroundColor DarkGray
