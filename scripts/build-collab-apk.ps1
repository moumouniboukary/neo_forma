#Requires -Version 5.1
param(
  [string]$OutName = "NeoForma-collaborateur.apk"
)
# APK release signee, API Render -- collab et commercants.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Mobile = Join-Path $Root "apps\mobile"
$AndroidDir = Join-Path $Mobile "android"
$KeyProps = Join-Path $AndroidDir "key.properties"
$Keystore = Join-Path $AndroidDir "upload-keystore.jks"
$OutDir = Join-Path $Root "dist\apk"
$ApiBase = "https://neoforma-api.onrender.com"
$AppName = "NeoForma"

if (Test-Path (Join-Path $Root ".gradle-home-fresh")) {
  $env:GRADLE_USER_HOME = (Resolve-Path (Join-Path $Root ".gradle-home-fresh")).Path
}

function Get-Keytool {
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $fromJava = Join-Path $env:JAVA_HOME "bin\keytool.exe"
  if ($env:JAVA_HOME -and (Test-Path $fromJava)) { return $fromJava }
  $studio = Join-Path $env:LOCALAPPDATA "Programs\Android\Android Studio\jbr\bin\keytool.exe"
  if (Test-Path $studio) { return $studio }
  throw "keytool introuvable (installe un JDK ou Android Studio)."
}

if ((Test-Path $KeyProps) -and (Test-Path $Keystore)) {
  $props = Get-Content $KeyProps -Raw
  if ($props -notmatch "storeFile=\.\./upload-keystore") {
    $props = $props -replace "storeFile=.*", "storeFile=../upload-keystore.jks"
    Set-Content -Path $KeyProps -Value $props.TrimEnd() -Encoding ASCII
  }
}

if (-not (Test-Path $KeyProps) -or -not (Test-Path $Keystore)) {
  Write-Host "Creation keystore upload (local, ne pas committer)..."
  $keytool = Get-Keytool
  $pass = "neoforma-upload-dev"
  if (-not (Test-Path $Keystore)) {
    & $keytool -genkeypair -v `
      -keystore $Keystore `
      -storepass $pass `
      -keypass $pass `
      -alias upload `
      -keyalg RSA -keysize 2048 -validity 10000 `
      -dname "CN=NeoForma, OU=Pilote, O=NeoForma, L=Ouagadougou, C=BF"
    if ($LASTEXITCODE -ne 0) { throw "keytool a echoue ($LASTEXITCODE)" }
  }
  @"
storePassword=$pass
keyPassword=$pass
keyAlias=upload
storeFile=../upload-keystore.jks
"@ | Set-Content -Path $KeyProps -Encoding ASCII
  Write-Host "Ecrit: $KeyProps"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $Mobile
try {
  flutter pub get
  flutter build apk --release `
    --dart-define=API_BASE=$ApiBase `
    --dart-define=APP_NAME=$AppName
  $apk = Join-Path $Mobile "build\app\outputs\flutter-apk\app-release.apk"
  if (-not (Test-Path $apk)) { throw "APK introuvable: $apk" }

  $collab = Join-Path $Root $OutName
  $dist = Join-Path $OutDir $OutName
  Copy-Item $apk $collab -Force
  Copy-Item $apk $dist -Force

  Write-Host "API_BASE=$ApiBase"
  Write-Host "APP_NAME=$AppName"
  Write-Host "APK release signee: $collab"
  Write-Host "Copie:              $dist"
  Write-Host "Si une version debug est deja installee, desinstalle-la d abord (autre signature)."
} finally {
  Pop-Location
}
