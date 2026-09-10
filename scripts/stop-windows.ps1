$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $PSScriptRoot
$PidFile = Join-Path $Project 'data/windows-scanner.pid'

Push-Location $Project
try { docker compose down } finally { Pop-Location }

$pidText = Get-Content $PidFile -ErrorAction SilentlyContinue
if ($pidText) {
    Stop-Process -Id ([int]$pidText) -Force -ErrorAction SilentlyContinue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}
