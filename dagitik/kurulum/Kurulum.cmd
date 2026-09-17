@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "CT_INTERACTIVE=0"
if "%~1"=="" set "CT_INTERACTIVE=1"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kurulum.ps1" %*
set "CT_EXIT=%ERRORLEVEL%"

if not "%CT_EXIT%"=="0" (
    echo.
    echo Kurulum tamamlanamadi. Hata kodu: %CT_EXIT%
    set "CT_INTERACTIVE=1"
)

if "%CT_INTERACTIVE%"=="1" pause
exit /b %CT_EXIT%
