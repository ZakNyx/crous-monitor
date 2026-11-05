@echo off
echo Arret du moniteur CROUS...
powershell.exe -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*crous_watcher.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Moniteur arrete.
timeout /t 2 > nul
