$ErrorActionPreference = 'Stop'

$Project = Split-Path -Parent $PSScriptRoot
$DataDir = Join-Path $Project 'data'
$PidFile = Join-Path $DataDir 'windows-scanner.pid'
$OutLog = Join-Path $DataDir 'windows-scanner.log'
$ErrLog = Join-Path $DataDir 'windows-scanner.error.log'

New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'history') | Out-Null

# Make the native BLE side self-healing on a fresh Windows profile.
py -3.11 -c "import bleak, xiaomi_ble" 2>$null
if ($LASTEXITCODE -ne 0) {
    py -3.11 -m pip install --upgrade -r (Join-Path $Project 'requirements-windows.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not install Windows BLE dependencies.' }
}

# Start Docker Desktop if it is installed but not already running. The wait
# below then gives its Linux engine time to become available.
$DockerDesktop = Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'
if (Test-Path $DockerDesktop) {
    Start-Process -FilePath $DockerDesktop -WindowStyle Hidden -ErrorAction SilentlyContinue
}

$existingPid = Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
$scannerRunning = $false
if ($existingPid -match '^\d+$') {
    $scannerRunning = $null -ne (Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue)
}

if (-not $scannerRunning) {
    $proc = Start-Process -FilePath 'py.exe' `
        -ArgumentList '-3.11', (Join-Path $Project 'scripts/windows_s400_scanner.py') `
        -WorkingDirectory $Project `
        -WindowStyle Hidden `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -PassThru
    Set-Content -Path $PidFile -Value $proc.Id -Encoding ascii
    Write-Host "Windows BLE scanner started (PID $($proc.Id))."
} else {
    Write-Host 'Windows BLE scanner already running.'
}

for ($i = 0; $i -lt 30; $i++) {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    docker info 2>&1 | Out-Null
    $dockerExit = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($dockerExit -eq 0) { break }
    if ($i -eq 29) { throw 'Docker Desktop is not ready.' }
    Start-Sleep -Seconds 2
}

Push-Location $Project
try {
    docker compose up -d --build
    if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
} finally {
    Pop-Location
}

Write-Host 'Xiaomi S400 Windows bridge + Garmin container are running.'
Write-Host 'Logs: docker compose logs -f --tail=200 scale'
