#Requires -Version 5.1
param(
  [string]$OutName = "NeoForma-collaborateur.apk"
)
# Build APK NeoForma collab aligné sur l'API Render (même ligne que flutter run collab).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Mobile = Join-Path $Root "apps\mobile"
$OutDir = Join-Path $Root "dist\apk"
$ApiBase = "https://neoforma-api.onrender.com"
$AppName = "NeoForma"

if (Test-Path (Join-Path $Root ".gradle-home-fresh")) {
  $env:GRADLE_USER_HOME = (Resolve-Path (Join-Path $Root ".gradle-home-fresh")).Path
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $Mobile
try {
  flutter pub get
  # Debug APK: installable sans keystore, meme API que le run collab
  flutter build apk --debug `
    --dart-define=API_BASE=$ApiBase `
    --dart-define=APP_NAME=$AppName
  $apk = Join-Path $Mobile "build\app\outputs\flutter-apk\app-debug.apk"
  if (-not (Test-Path $apk)) { throw "APK introuvable: $apk" }

  $collab = Join-Path $Root $OutName
  $dist = Join-Path $OutDir $OutName
  Copy-Item $apk $collab -Force
  Copy-Item $apk $dist -Force

  Write-Host "API_BASE=$ApiBase"
  Write-Host "APP_NAME=$AppName"
  Write-Host "APK collab: $collab"
  Write-Host "Copie:      $dist"
} finally {
  Pop-Location
}
