@echo off
setlocal EnableExtensions
rem Tek dosya kurulumun (IExpress SFX) ic baslaticisi: ZIP'i gecici klasore
rem acar, indirme isaretini kaldirir ve kurulum sihirbazini calistirir.

set "CT_HEDEF=%TEMP%\CalismaTakipKurulum-%RANDOM%%RANDOM%"
mkdir "%CT_HEDEF%" 2>nul

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%~dp0Calisma-Takip-Dagitik-Kurulum.zip' -DestinationPath '%CT_HEDEF%' -Force; Get-ChildItem -LiteralPath '%CT_HEDEF%' -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"

if not exist "%CT_HEDEF%\Kur.ps1" goto hata
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CT_HEDEF%\Kur.ps1"
rd /s /q "%CT_HEDEF%" 2>nul
exit /b 0

:hata
echo.
echo Kurulum dosyalari acilamadi.
echo Paketi elle acip Kur.cmd dosyasini calistirabilirsin.
pause
exit /b 1
