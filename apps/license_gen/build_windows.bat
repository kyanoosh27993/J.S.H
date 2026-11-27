@echo off
REM ساخت نسخه نهایی exe مولد کد فعال‌سازی J.S.H (ویندوز)
REM پیش‌نیاز: Flutter SDK + Visual Studio Build Tools (C++ desktop)
chcp 65001 >nul
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [خطا] Flutter پیدا نشد — نصب Flutter و افزودن flutter\bin به PATH.
  pause
  exit /b 1
)

flutter pub get
if errorlevel 1 (
  echo [خطا] دریافت بسته‌ها ناموفق بود.
  pause
  exit /b 1
)

flutter build windows --release
if errorlevel 1 (
  echo [خطا] بیلد ناموفق — docs/TROUBLESHOOTING.md را ببینید.
  pause
  exit /b 1
)

echo.
echo [موفق] خروجی: %~dp0build\windows\x64\runner\Release\
echo کل محتوای این پوشه را (همراه DLLها) منتقل کنید — فایل اجرایی: license_gen.exe
start "" explorer "%~dp0build\windows\x64\runner\Release\"
pause
