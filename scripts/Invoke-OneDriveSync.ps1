#Requires -Version 5.1

param(
    [string]$ExecutablePath = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe' } else { '' })
)

if (-not $ExecutablePath -or -not (Test-Path -Path $ExecutablePath)) {
    Write-Warning "OneDrive.exe wurde nicht gefunden (gesucht unter '$ExecutablePath'). Ueberspringe Sync-Anstoss."
    exit 0
}

Write-Host "Stosse OneDrive-Sync an: beende und starte OneDrive neu ($ExecutablePath)."
Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process -FilePath $ExecutablePath -ArgumentList '/background'
Write-Host "OneDrive neu gestartet. Das erzwingt einen frischen Dateicheck, ist aber kein garantierter, blockierender Sync-Abschluss - siehe README.md, Abschnitt 'Regelmaessige Automatisierung'."
