#Requires -Version 5.1
<#
.SYNOPSIS
  APK release signée commerçants (même build que npm run mobile:apk).
#>
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "build-collab-apk.ps1") -OutName "NeoForma-commercant.apk"
