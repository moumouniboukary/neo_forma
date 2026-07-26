# Backup Postgres NeoForma (Windows / Docker).
# Usage: powershell -File scripts/backup-postgres.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutDir = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { Join-Path $Root "backups" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Stamp = Get-Date -Format "yyyyMMddTHHmmssZ"
$File = Join-Path $OutDir "neoforma-$Stamp.sql"

$running = docker ps --format "{{.Names}}" | Select-String -Pattern "^neoforma-postgres$"
if (-not $running) {
  Write-Error "Conteneur neoforma-postgres introuvable. Démarrez docker compose."
}

Write-Host "[backup] pg_dump → $File"
docker exec neoforma-postgres pg_dump -U neoforma neoforma | Set-Content -Path $File -Encoding utf8

# Compression simple si gzip dispo
if (Get-Command gzip -ErrorAction SilentlyContinue) {
  gzip -f $File
  $File = "$File.gz"
}

# Garde les 14 plus récents
Get-ChildItem $OutDir -Filter "neoforma-*" | Sort-Object LastWriteTime -Descending |
  Select-Object -Skip 14 | Remove-Item -Force

Write-Host "[backup] OK $File"
