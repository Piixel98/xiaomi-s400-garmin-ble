$ErrorActionPreference = 'Stop'

$Project = Split-Path -Parent $PSScriptRoot
$StartScript = Join-Path $Project 'scripts/start-windows.ps1'
$TaskName = 'Xiaomi S400 Garmin bridge'

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StartScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Autostart installed: $TaskName"
Write-Host "It will start Docker Desktop, the Windows BLE scanner and the Garmin container at logon."
