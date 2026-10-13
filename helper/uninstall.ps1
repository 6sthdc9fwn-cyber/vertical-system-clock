# Vertical System Clock - disinstallazione dell'helper / helper removal

$target = Join-Path $env:LOCALAPPDATA 'VerticalSystemClock'
$shortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'Vertical System Clock helper.lnk'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*VerticalSystemClock*sysinfo.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Helper rimosso / Helper removed.' -ForegroundColor Green
