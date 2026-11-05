@echo off
chcp 65001 > nul
title CROUS Housing Live Monitor
color 0B
echo.
echo ==============================================================
echo        CROUS Real-Time Housing Monitor
echo ==============================================================
echo.
echo Lancement du script de surveillance...
echo Verifications toutes les 10 secondes.
echo Pour quitter, fermez simplement cette fenetre.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0crous_watcher.ps1"
pause
