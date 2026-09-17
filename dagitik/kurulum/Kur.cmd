@echo off
setlocal EnableExtensions
cd /d "%~dp0"
start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Kur.ps1"
exit /b 0
