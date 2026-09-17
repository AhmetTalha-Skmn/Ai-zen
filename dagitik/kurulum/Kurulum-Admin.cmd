@echo off
setlocal EnableExtensions
cd /d "%~dp0"
rem Sirket kurulumu: hatirlatma yok, ekran kilidi kapali. Mevcut kurulumun turu ve
rem -KurulumTuru parametresi bunun onune gecer (Kurulum.ps1).
set "CT_KURULUM_TURU=Sirket"

echo.
echo  Aizen - SIRKET YONETICI (admin) kurulumu
echo  Bu bilgisayar merkez olur: diger bilgisayarlarin ozetlerini burada gorursun.
echo  Ag dinleyicisi icin Windows yonetici onayi isteyecek.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kurulum.ps1" -Rol Admin %*
set "CT_EXIT=%ERRORLEVEL%"

if not "%CT_EXIT%"=="0" (
    echo.
    echo Kurulum tamamlanamadi. Hata kodu: %CT_EXIT%
)
pause
exit /b %CT_EXIT%
