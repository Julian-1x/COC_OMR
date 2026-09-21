# Build a release APK with school API URL baked in from secrets.json
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$secrets = Join-Path $root "secrets.json"

if (-not (Test-Path $secrets)) {
    Write-Host "Missing secrets.json - copy secrets.json.example and set API_BASE_URL."
    exit 1
}

Set-Location $root
flutter build apk --release --dart-define-from-file=$secrets @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apkSource = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSource)) {
    Write-Host "Build finished but APK not found at $apkSource"
    exit 1
}

# Copy to dist/ with versioned name; remove older coc-omr-v*.apk so only one install file remains.
$pubspec = Get-Content (Join-Path $root "pubspec.yaml") -Raw
$version = "unknown"
if ($pubspec -match '(?m)^version:\s*(\S+)') {
    $version = $Matches[1]
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$apkName = "coc-omr-v$version.apk"
$apkDest = Join-Path $dist $apkName
Copy-Item $apkSource $apkDest -Force

$removed = @()
Get-ChildItem -Path $dist -Filter "coc-omr-v*.apk" -File | ForEach-Object {
    if ($_.Name -ne $apkName) {
        Remove-Item $_.FullName -Force
        $removed += $_.Name
    }
}

Write-Host ""
Write-Host "APK: $apkDest"
if ($removed.Count -gt 0) {
    Write-Host "Removed older dist APKs: $($removed -join ', ')"
}
