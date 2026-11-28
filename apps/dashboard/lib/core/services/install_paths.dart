/// فاز ۸ — بند ۰: تعیین پوشه پایه ذخیره‌سازی داده‌ها
///
/// پیش‌فرض: `getApplicationSupportDirectory()` (رفتار قبلی برنامه).
/// حالت پرتابل (نصب‌کننده بند ۰): اگر فایل خالی `portable.marker` کنار فایل
/// اجرایی برنامه وجود داشته باشد، نصب‌کننده Inno Setup آن را در پوشه نصب
/// می‌نویسد و در نتیجه پایگاه‌داده (`jsh_dashboard.db` و فایل‌های -wal/-shm)
/// در همان پوشه نصبِ انتخاب‌شده توسط کاربر ساخته می‌شود — نه در AppData.
///
/// نکته امنیتی: این فقط «محل ذخیره» را تغییر می‌دهد؛ HMAC رکورد لایسنس و
/// نگهبان تاریخ همچنان روی اثر انگشت سخت‌افزار کار می‌کنند و کپی کردن پوشه
/// نصب روی رایانه دیگر برنامه را قفل می‌کند.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class InstallPaths {
  InstallPaths._();

  /// نام فایل نشانگر حالت پرتابل — نصب‌کننده آن را کنار exe می‌نویسد
  static const String markerFileName = 'portable.marker';

  /// فقط برای تست — در اجرای واقعی null است.
  /// اگر غیر null باشد، به‌جای `Platform.resolvedExecutable` استفاده می‌شود
  /// تا منطق مسیر بدون نیاز به exe واقعی قابل تست باشد.
  static String? debugExeDir;

  /// پوشه کنار فایل اجرایی (مثلاً C:\...\JSHDashboard در نصب ویندوز)
  static Directory exeDirectory() {
    final override = debugExeDir;
    if (override != null && override.isNotEmpty) return Directory(override);
    return File(Platform.resolvedExecutable).parent;
  }

  /// آیا حالت پرتابل فعال است؟ (فایل نشانگر کنار exe موجود باشد)
  static Future<bool> isPortable() async {
    try {
      final marker = File('${exeDirectory().path}${Platform.pathSeparator}$markerFileName');
      return await marker.exists();
    } catch (_) {
      return false;
    }
  }

  /// پوشه پایه داده‌ها:
  ///   پرتابل → همان پوشه نصب (بند ۰: دیتابیس در پوشه نصب)
  ///   غیر پرتابل → ApplicationSupport (رفتار قبلی)
  static Future<String> resolveBaseDir() async {
    if (await isPortable()) return exeDirectory().path;
    final support = await getApplicationSupportDirectory();
    return support.path;
  }
}
