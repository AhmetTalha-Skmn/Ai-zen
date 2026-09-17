@echo off
setlocal EnableExtensions
cd /d "%~dp0"
rem Sirket kurulumu: hatirlatma yok, ekran kilidi kapali. Mevcut kurulumun turu ve
rem -KurulumTuru parametresi bunun onune gecer (Kurulum.ps1).
set "CT_KURULUM_TURU=Sirket"

echo.
echo  Aizen - SIRKET CALISANI kurulumu
echo  Bu bilgisayarin calisma suresi olculur.
echo  Bir merkeze baglanmak istege baglidir: yoneticiden aldigin kodu girersin ve
echo  ne gonderilecegini gosteren onay ekranini kabul edersin. Onay vermezsen
echo  hicbir veri gonderilmez, takip yalnizca bu bilgisayarda kalir.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kurulum.ps1" -Rol Kullanici %*
set "CT_EXIT=%ERRORLEVEL%"

if not "%CT_EXIT%"=="0" (
    echo.
    echo Kurulum tamamlanamadi. Hata kodu: %CT_EXIT%
)
pause
exit /b %CT_EXIT%
