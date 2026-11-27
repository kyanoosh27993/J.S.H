# تمام دستورات لازم — مولد کد فعال‌سازی J.S.H

این سند مرجع کامل دستورات است. اگر فقط یک سند را می‌خوانید، همین را بخوانید.

---

## ۱) پیش‌نیازها (فقط بار اول)

| پیش‌نیاز | بررسی نصب بودن | توضیح |
|---|---|---|
| Flutter SDK نسخه پایدار (۳.۳۵ یا بالاتر پیشنهاد می‌شود) | `flutter --version` | [flutter.dev](https://docs.flutter.dev/get-started/install/windows) |
| Visual Studio Build Tools با بار کاری «Desktop development with C++» | `flutter doctor` | برای بیلد exe ویندوز ضروری است؛ خود Visual Studio کامل لازم نیست |
| فعال‌سازی پشتیبانی دسکتاپ ویندوز | `flutter config --enable-windows-desktop` | یک بار پس از نصب Flutter |
| Git | `git --version` | برای دریافت و ذخیره مخزن |

دستور سلامت کل سیستم:

```powershell
flutter doctor
```

هر سطر با تیک سبز یعنی آماده است؛ بخش «Visual Studio - develop Windows apps» برای بیلد exe لازم است.

---

## ۲) دریافت سورس

```powershell
git clone https://github.com/kyanoosh27993/J.S.H.git
cd J.S.H\apps\license_gen
flutter pub get
```

---

## ۳) اجرای برنامه (حالت توسعه)

```powershell
cd apps\license_gen
flutter run -d windows
```

یا در ویندوز دابل‌کلیک روی **`run_windows.bat`** (در همین پوشه) — خودش `pub get` و اجرا را انجام می‌دهد.

---

## ۴) ساخت exe مستقل (خروجی نهایی)

```powershell
cd apps\license_gen
flutter build windows --release
```

خروجی: `apps\license_gen\build\windows\x64\runner\Release\` — کل محتوای این پوشه (به‌همه فایل‌های DLL کنارش) را می‌توان در قالب یک پوشه به هر ویندوز دیگر منتقل کرد؛ فایل اجرایی `license_gen.exe` است.

بسته‌بندی زیپ (اختیاری):

```powershell
Compress-Archive -Path apps\license_gen\build\windows\x64\runner\Release\* `
  -DestinationPath jsh-license-gen-windows-x64.zip -Force
```

یا دابل‌کلیک روی **`build_windows.bat`** — بیلد می‌کند و پوشه خروجی را باز می‌کند.

---

## ۵) دریافت exe آماده بدون بیلد (توصیه‌شده)

هر تگ نسخه (مثل `v0.11.0`) روی گیت‌هاب، به‌صورت خودکار exe مولد را در بخش Releases منتشر می‌کند:

```text
در مرورگر:
https://github.com/kyanoosh27993/J.S.H/releases
فایل: jsh-license-gen-windows-x64.zip
```

---

## ۶) تست‌ها و بررسی کیفیت

```powershell
# تست هسته فعال‌سازی (۱۰ تست — ساخت/اعتبارسنجی/دستکاری/انقضا/دستگاه دیگر/...)
cd packages\activation_core
flutter test

# تست برنامه مولد
cd apps\license_gen
flutter test

# بررسی ایستا (بدون خطا باید باشد)
flutter analyze
```

اجرای سریع هسته فقط با Dart (بدون Flutter):

```powershell
cd packages\activation_core
dart test
```

---

## ۷) ابزار خط فرمان — تولید کد بدون باز کردن برنامه

برای خودکارسازی یا ساخت سریع کد، ابزار `packages/activation_core/example/make_code.dart` دقیقاً همان خروجی برنامه گرافیکی را می‌دهد:

```powershell
# تولید کد با تاریخ شمسی:
cd packages\activation_core
dart run example/make_code.dart --device 8f3b1c2d4e5f6a7b8c9d0e1f2a3b4c5d --expiry 1406/09/04

# تولید کد با تاریخ میلادی و سقف نصب مجدد ۱:
dart run example/make_code.dart --device 8f3b1c2d4e5f6a7b8c9d0e1f2a3b4c5d --expiry 2027-11-25 --reinstalls 1

# بررسی یک کد (مثلاً وقتی خریدار می‌گوید «کد کار نمی‌کند»):
dart run example/make_code.dart --verify JSH-980G0M-MV02JA-AVRMS4-78QTY8-9A6TBW-1YZBS0 --device 8f3b1c2d4e5f6a7b8c9d0e1f2a3b4c5d
```

- تاریخ شمسی با `/` یا `-`؛ ارقام فارسی هم پذیرفته می‌شود.
- `--reinstalls` از ۰ تا ۲۵۵؛ ۰ یعنی «پیش‌فرض برنامه (۳ بار)».
- کد تولیدشده همیشه خودآزمایی می‌شود (اگر امضا درست نباشد، ابزار خطا می‌دهد).
- این ابزار در بانک تاریخچه ثبت نمی‌کند؛ اگر می‌خواهید کد در تاریخچه باشد، از برنامه گرافیکی استفاده کنید.

---

## ۸) پشتیبان‌گیری و بازیابی بانک کدها

مکان بانک (ویندوز): زیر پوشه `AppData\Roaming` — پیدا کردن مسیر دقیق:

```powershell
Get-ChildItem $env:APPDATA -Recurse -Filter jsh_license_gen.db -ErrorAction SilentlyContinue | Select-Object FullName
```

پشتیبان‌گیری (مثال — مسیر را با خروجی بالا جایگزین کنید):

```powershell
Copy-Item "$env:APPDATA\<نام پکیج>\jsh_license_gen.db" "D:\Backup\jsh_license_gen_$(Get-Date -Format yyyyMMdd).db"
```

بازیابی: برنامه را ببندید، فایل پشتیبان را روی مسیر اصلی کپی کنید، برنامه را باز کنید.

جزئیات کامل اسکیما: [`DATABASE.md`](DATABASE.md)

---

## ۹) خروجی CSV

از رابط برنامه: تب «تاریخچه کدها» → دکمه **خروجی CSV** → فایل در پوشه Documents ذخیره می‌شود:

```text
C:\Users\<نام کاربری>\Documents\jsh_activation_codes_<زمان>.csv
```

ستون‌ها: `code, buyer, expiry, max_reinstalls, installs_reported, created_at, note`

---

## ۱۰) انتشار نسخه جدید (CI خودکار)

با تگ زدن، گیت‌هاب Actions خودش تست + بیلد exe مولد و برنامه اصلی را می‌سازد و در Release می‌گذارد:

```powershell
git tag v0.12.0
git push origin v0.12.0
```

(پیش از تگ، کامیت‌ها را push کنید: `git push origin main`)

فایل CI: `.github/workflows/build.yml` — شامل job جداگانه «بیلد مولد کد فعال‌سازی — Windows exe» است.

---

## ۱۱) کار جداگانه روی مولد (شاخه مستقل)

برای تغییر دادن مولد بدون دست‌زدن به برنامه اصلی:

```powershell
git checkout -b license-gen-dev
# تغییرات را انجام دهید (docs/CUSTOMIZATION.md)
cd packages\activation_core ; flutter test
cd ..\..\apps\license_gen ; flutter test ; flutter analyze
git add -A
git commit -m "مولد: توضیح تغییر"
git push origin license-gen-dev
```

پس از اطمینان، در گیت‌هاب Pull Request به `main` بزنید یا مستقیم merge کنید.

> **هشدار:** اگر تغییری در `packages/activation_core` داده‌اید، آن تغییر برای برنامه اصلی هم اعمال می‌شود (هسته مشترک). چرخش کلید امضا = باطل شدن همه کدهای قبلی؛ قبل از انجام، [`CUSTOMIZATION.md`](CUSTOMIZATION.md) را کامل بخوانید.
