@echo off
REM اجرای برنامه مولد کد فعال‌سازی J.S.H روی ویندوز (حالت توسعه)
REM پیش‌نیاز: Flutter SDK در PATH
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

flutter run -d windows
pause
