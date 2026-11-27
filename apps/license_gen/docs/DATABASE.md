# بانک تاریخچه کدها و خروجی CSV — مولد کد فعال‌سازی

مولد کد، همه کدهای صادرشده را در یک بانک SQLite محلی ثبت می‌کند تا هر زمان بدانید چه کدی، برای چه خریداری، با چه اعتباری داده‌اید (بند ۲ درخواست صاحب پروژه).

---

## ۱) مکان فایل بانک

| OS | مکان | نام فایل |
|---|---|---|
| ویندوز | زیر `AppData\Roaming` (پوشه پشتیبانی برنامه) | `jsh_license_gen.db` |
| لینوکس | زیر پوشه پشتیبانی برنامه در home | `jsh_license_gen.db` |

پیدا کردن مسیر دقیق در ویندوز (PowerShell):

```powershell
Get-ChildItem $env:APPDATA -Recurse -Filter jsh_license_gen.db -ErrorAction SilentlyContinue | Select-Object FullName
```

این بانک فقط روی رایانه سازنده وجود دارد و به خریدار داده نمی‌شود.

---

## ۲) اسکیمای جدول `activation_codes`

```sql
CREATE TABLE IF NOT EXISTS activation_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,          -- خود کد فعال‌سازی (تکراری نمی‌شود)
  device_short TEXT DEFAULT '',       -- اثر کوتاه دستگاه: ۸ حرف اول hex هش دستگاه
  buyer TEXT DEFAULT '',              -- نام خریدار
  expiry TEXT NOT NULL,               -- پایان اعتبار به شمسی «1406/09/04»
  max_reinstalls INTEGER DEFAULT 0,   -- سقف نصب مجدد (۰ = پیش‌فرض)
  note TEXT DEFAULT '',               -- یادداشت آزاد شما
  installs_reported INTEGER DEFAULT 0,-- شمار نصب‌های گزارش‌شده خریدار
  created_at TEXT NOT NULL            -- زمان صدور ISO-8601
);
```

رفتارهای مهم:

- هر کد `UNIQUE` است — با یک شناسه دستگاه چند بار کد بسازید، هرکدام سطر جدا دارند (مثلاً تمدید سال بعد).
- نمایش تاریخچه با مرتب‌سازی `id DESC` است (جدیدترین بالا).
- دکمه «ثبت نصب» (+) در تب تاریخچه فقط `installs_reported` را یکی اضافه می‌کند (`CodeDb.bumpInstalls`) — شمارنده دستی است چون برنامه آفلاین است و خبر نصب را خریدار می‌دهد.

---

## ۳) پشتیبان‌گیری و بازیابی

```powershell
# پشتیبان روزانه/هفتگی پیشنهاد می‌شود:
Copy-Item "<مسیر پوشه پشتیبانی>\jsh_license_gen.db" "D:\Backup\jsh_license_gen_$(Get-Date -Format yyyyMMdd).db"
```

بازیابی:

1. برنامه مولد را ببندید.
2. فایل پشتیبان را روی مسیر اصلی کپی کنید (فایل قبلی را نگه دارید).
3. برنامه را باز کنید — تاریخچه کامل برمی‌گردد.

خروجی CSV هم خودش یک آرشیو خوانا است؛ هفته‌ای یک‌بار گرفتنش توصیه می‌شود.

---

## ۴) خروجی CSV

تب «تاریخچه کدها» → **خروجی CSV**. فایل در پوشه Documents ذخیره می‌شود:

```text
C:\Users\<کاربر>\Documents\jsh_activation_codes_<timestamp>.csv
```

سطر اول (سرستون‌ها):

```csv
code,buyer,expiry,max_reinstalls,installs_reported,created_at,note
```

مقادیر با گیومه محصور می‌شوند و گیومه داخلی دوبل می‌شود (`""`) پس ویرگول/گیومه در نام خریدار یا یادداشت، ستون‌ها را نمی‌شکند. فایل با Excel/LibreOffice باز می‌شود (اگر کد فارسی به‌هم‌ریخته بود، در Excel از «Data → From Text/CSV» با UTF-8 باز کنید).

---

## ۵) تغییر دادن بانک (مهاجرت اسکیما)

نسخه بانک در `main.dart` به‌صورت `OpenDatabaseOptions(version: 1)` است. برای افزودن ستون جدید (مثلاً شماره تماس خریدار):

1. `version` را به `2` تغییر دهید و `onUpgrade` اضافه کنید:

```dart
await databaseFactory.openDatabase(
  p.join(dir.path, 'jsh_license_gen.db'),
  options: OpenDatabaseOptions(
    version: 2,
    onUpgrade: (db, from, to) async {
      if (from < 2) {
        await db.execute(
            'ALTER TABLE activation_codes ADD COLUMN buyer_phone TEXT DEFAULT \'\'');
      }
    },
  ),
);
```

2. فرم تولید و جدول تاریخچه را به‌روز کنید (راهنمای کامل: [`CUSTOMIZATION.md`](CUSTOMIZATION.md)).
3. بانک‌های موجود خودکار مهاجرت می‌شوند؛ داده از بین نمی‌رود.

---

## ۶) پرسش‌های پرتکرار

- **«بانک را اشتباهی پاک کردم»** — اگر پشتیبان دارید بازیابی کنید؛ اگر نه، CSV آخرین نسخه حقیقت است (کدها هنوز معتبرند چون اعتبارسنجی در برنامه اصلی مستقل از این بانک است — بانک فقط گزارش‌ساز است).
- **«خریدار می‌گوید کد کار می‌کند ولی در تاریخچه نیست»** — احتمالاً کد با ابزار خط فرمان ساخته شده که ثبت در بانک ندارد؛ از این پس برای ثبت در تاریخچه از برنامه گرافیکی بسازید.
- **«دو کد برای یک دستگاه ساختم»** — مشکلی نیست؛ آخرین کدی که خریدار وارد کند اثر می‌کند و در برنامه اصلی جایگزین می‌شود.
