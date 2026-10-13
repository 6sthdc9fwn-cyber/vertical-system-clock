# Vertical System Clock - installazione dell'helper / helper installation
# Copia l'helper in %LOCALAPPDATA%\VerticalSystemClock, lo avvia e lo fa partire a ogni accesso a Windows.
# Copies the helper to %LOCALAPPDATA%\VerticalSystemClock, starts it and runs it at every Windows sign-in.

$ErrorActionPreference = 'Stop'
$target = Join-Path $env:LOCALAPPDATA 'VerticalSystemClock'
$startup = [Environment]::GetFolderPath('Startup')
$shortcut = Join-Path $startup 'Vertical System Clock helper.lnk'

# ferma un'eventuale versione già in esecuzione (prima l'avviatore, che altrimenti la riavvierebbe)
# stop a running copy (the launcher first, otherwise it would restart the helper)
Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" |
    Where-Object { $_.CommandLine -like '*VerticalSystemClock*start-helper.vbs*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*VerticalSystemClock*sysinfo.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'sysinfo.ps1'), (Join-Path $PSScriptRoot 'start-helper.vbs') $target -Force
Get-ChildItem $target | Unblock-File

$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($shortcut)
$lnk.TargetPath = Join-Path $target 'start-helper.vbs'
$lnk.WorkingDirectory = $target
$lnk.Description = 'Vertical System Clock helper'
$lnk.Save()

Start-Process wscript.exe -ArgumentList "`"$(Join-Path $target 'start-helper.vbs')`""
Start-Sleep -Seconds 6

try {
    Invoke-WebRequest 'http://127.0.0.1:47811/stats' -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host ''
    Write-Host 'OK: helper installato e attivo / helper installed and running.' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host 'Helper installato, ma non risponde ancora: riprova tra qualche secondo.' -ForegroundColor Yellow
    Write-Host 'Helper installed, but not answering yet: try again in a few seconds.' -ForegroundColor Yellow
}
Write-Host "Cartella / Folder: $target"
Write-Host 'Per temperature e ventole installa LibreHardwareMonitor (vedi README).'
Write-Host 'For temperatures and fans install LibreHardwareMonitor (see README).'
