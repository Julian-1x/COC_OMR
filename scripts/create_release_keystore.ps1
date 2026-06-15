# Creates android/app/upload-keystore.jks for release APK signing.
# Run once, then copy android/key.properties.example to android/key.properties.

$ErrorActionPreference = "Stop"
$keystore = Join-Path $PSScriptRoot "..\android\app\upload-keystore.jks"

if (Test-Path $keystore) {
    Write-Host "Keystore already exists: $keystore"
    exit 0
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    Write-Error "keytool not found. Install a JDK (Android Studio includes one)."
}

Write-Host "Creating release keystore at $keystore"
Write-Host "You will be asked for a keystore password — save it in a password manager."

& keytool -genkey -v `
    -keystore $keystore `
    -alias coc-omr `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storetype JKS `
    -dname "CN=COC OMR, OU=IT, O=Cagayan de Oro College, L=Cagayan de Oro, ST=Misamis Oriental, C=PH"

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Copy android/key.properties.example to android/key.properties"
Write-Host "  2. Fill in storePassword and keyPassword"
Write-Host "  3. flutter build apk --release ..."
