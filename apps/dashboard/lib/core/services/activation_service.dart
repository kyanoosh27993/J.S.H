/// سرویس فعال‌سازی با کد دستگاه‌محور — فاز ۱ نقشه راه نسخه ۲ (بندهای ۲، ۳، ۴، ۱۸)
///
/// جریان: نصب → ویزارد اطلاعات پایه → صفحه فعال‌سازی (نمایش شناسه دستگاه + درخواست کد)
/// → ورود کد معتبر → اجرا. پس از فعال‌سازی، هر بار اجرا:
///   ۱) نگهبان تاریخ (ضد عقب‌بردن تاریخ سیستم — بند ۳)
///   ۲) بررسی اعتبار کد نسبت به دستگاه و تاریخ
///   ۳) هشدار ۷ روز مانده به پایان اعتبار (بند ۱۸)
library;

import 'dart:io';

import 'package:activation_core/activation_core.dart';

import '../constants.dart';
import '../models.dart';
import '../repos.dart';
import '../utils.dart';
import 'license_service.dart';
import 'supervisor_service.dart';

/// وضعیت فعال‌سازی نسخه نصب‌شده
enum ActivationStatus {
  notActivated, // هنوز کد وارد نشده
  active, // فعال و معتبر
  expired, // اعتبار تمام شده
}

class ClockTamperedException implements Exception {
  final String lastSeen;
  final String now;
  ClockTamperedException(this.lastSeen, this.now);
  @override
  String toString() => 'CLOCK_TAMPERED';
}

class ActivationService {
  ActivationService._();

  /// شناسه کامل دستگاه — برای تولید کد فعال‌سازی در برنامه جانبی
  static Future<String> deviceId() => LicenseService.fingerprint();

  /// شناسه نمایشی چندقطعه‌ای برای خوانایی و تایپ آسان‌تر
  static String displayDeviceId(String raw) {
    final chunks = <String>[];
    for (var i = 0; i < raw.length; i += 8) {
      final end = (i + 8 > raw.length) ? raw.length : i + 8;
      chunks.add(raw.substring(i, end));
    }
    return chunks.join('-');
  }

  /// نگهبان تاریخ سیستم — بیشینه تاریخ دیده‌شده ذخیره و مقایسه می‌شود.
  /// اگر تاریخ سیستم بیش از یک روز عقب‌تر از آخرین اجرا باشد = دستکاری
  static Future<DateTime?> clockGuard(LicenseState state,
      {DateTime? now}) async {
    final today = (now ?? DateTime.now());
    final todayDay = DateTime(today.year, today.month, today.day);
    var lastSeen = DateTime(1970, 1, 1);
    if (state.lastSeenDate.isNotEmpty) {
      lastSeen = DateTime.tryParse(state.lastSeenDate) ?? lastSeen;
    }
    // آینه خارج از رکورد لایسنس — دو مکان مستقل (قاعده ۱۲)
    final mirror =
        DateTime.tryParse(await SettingsRepo.get('last_seen_mirror')) ?? lastSeen;
    if (mirror.isAfter(lastSeen)) lastSeen = mirror;
    final hidden = DateTime.tryParse(await _hiddenLastSeen()) ?? lastSeen;
    if (hidden.isAfter(lastSeen)) lastSeen = hidden;

    if (todayDay.isBefore(lastSeen.subtract(const Duration(hours: 30)))) {
      throw ClockTamperedException(
          lastSeen.toIso8601String(), todayDay.toIso8601String());
    }
    // به‌روزرسانی فقط وقتی جلوتر است
    if (todayDay.isAfter(lastSeen)) {
      state.lastSeenDate = todayDay.toIso8601String();
      await SettingsRepo.set('last_seen_mirror', state.lastSeenDate);
      await _writeHiddenLastSeen(state.lastSeenDate);
    }
    return lastSeen.isAfter(DateTime(1970, 1, 1)) ? lastSeen : null;
  }

  static Future<String> _hiddenLastSeenPath() async {
    if (Platform.isWindows) {
      final pd = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
      return '$pd\\JSH\\.activation_guard';
    }
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.config/jsh/.activation_guard';
  }

  static Future<String> _hiddenLastSeen() async {
    try {
      final f = File(await _hiddenLastSeenPath());
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return '';
  }

  static Future<void> _writeHiddenLastSeen(String iso) async {
    try {
      final f = File(await _hiddenLastSeenPath());
      await f.parent.create(recursive: true);
      await f.writeAsString(iso);
      if (Platform.isWindows) {
        try {
          await Process.run('attrib', ['+h', f.path]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// بررسی وضعیت فعال‌سازی ذخیره‌شده (بدون ورود کد) — برای هر اجرا
  static Future<ActivationStatus> statusOf(LicenseState state,
      {DateTime? now, DateTime? lastSeen}) async {
    if (!state.activated) return ActivationStatus.notActivated;
    final today = now ?? DateTime.now();
    final seen = lastSeen ?? DateTime.tryParse(state.lastSeenDate);
    final r = ActivationCodec.verify(
      code: state.activationCode,
      deviceId: state.fingerprint,
      today: today,
      lastSeen: seen,
    );
    if (r.ok) return ActivationStatus.active;
    if (r.check == ActivationCheck.expired) return ActivationStatus.expired;
    // کد ذخیره‌شده دیگر معتبر نیست (دستگاه عوض شده / دستکاری) → قفل فعال‌سازی
    return ActivationStatus.expired;
  }

  /// فعال‌سازی با کد — تنها راه ورود به برنامه (بند ۴)
  /// خروجی: پیام خطای فارسی یا null در صورت موفقیت
  static Future<String?> activate(LicenseState state, String codeInput,
      {DateTime? now}) async {
    final code = toEnglishDigits(codeInput.trim()).toUpperCase();
    if (code.isEmpty) return 'کد فعال‌سازی را وارد کنید.';
    final today = now ?? DateTime.now();
    final lastSeen = state.lastSeenDate.isNotEmpty
        ? DateTime.tryParse(state.lastSeenDate)
        : null;
    final r = ActivationCodec.verify(
      code: code,
      deviceId: state.fingerprint,
      today: today,
      lastSeen: lastSeen,
    );
    switch (r.check) {
      case ActivationCheck.ok:
        break;
      case ActivationCheck.badFormat:
        return 'قالب کد فعال‌سازی درست نیست. کد باید به شکل JSH-XXXXXX-… باشد.';
      case ActivationCheck.tampered:
        return 'این کد فعال‌سازی معتبر نیست (دستکاری‌شده). با پشتیبانی تماس بگیرید.';
      case ActivationCheck.wrongDevice:
        return 'این کد برای دستگاه دیگری صادر شده است. شناسه دستگاه همین رایانه را برای سازنده بفرستید.';
      case ActivationCheck.expired:
        return 'اعتبار این کد فعال‌سازی به پایان رسیده است. برای تمدید با پشتیبانی تماس بگیرید.';
      case ActivationCheck.wrongVersion:
        return 'این کد برای نسخه دیگری از برنامه است.';
    }
    state.activationCode = code;
    state.activationExpiry = r.expiry?.toIso8601String() ?? '';
    state.activatedAt = today.toIso8601String();
    state.lastSeenDate = DateTime(today.year, today.month, today.day)
        .toIso8601String();
    await LicenseRepo.save(state);
    await LicenseIntegrity.write();
    await SettingsRepo.set('last_seen_mirror', state.lastSeenDate);
    await _writeHiddenLastSeen(state.lastSeenDate);
    await AuditRepo.log('activation_success',
        'کد ${ActivationCodec.shortDeviceId(code)} — انقضا ${state.activationExpiry}');
    return null;
  }

  /// روزهای باقیمانده اعتبار (برای صفحه پشتیبانی و هشدار ۷ روز — بند ۱۸)
  static int remainingDays(LicenseState state, {DateTime? now}) {
    if (state.activationExpiry.isEmpty) return 0;
    final exp = DateTime.tryParse(state.activationExpiry);
    if (exp == null) return 0;
    final today = now ?? DateTime.now();
    final d = DateTime(exp.year, exp.month, exp.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    return d;
  }

  /// پیام هشدار پایان اعتبار — دقیقاً مطابق متن درخواست صاحب پروژه (بند ۱۸)
  static String expiryWarningMessage(int remainingDays) {
    return 'فقط ${toPersianDigits('$remainingDays')} روز تا اتمام اعتبار کد فعال‌سازی '
        'برنامه شما باقی مانده است.\n'
        'لطفاً هرچه سریع‌تر جهت تمدید و فعال‌سازی با شماره تماس '
        '${toPersianDigits(VendorInfo.supportPhone)} تماس حاصل فرمائید.';
  }

  static String expiryLockMessage() {
    return 'اعتبار کد فعال‌سازی برنامه شما به پایان رسیده است.\n\n'
        'برای تمدید و دریافت کد فعال‌سازی جدید، با پشتیبانی تماس بگیرید:\n'
        '${VendorInfo.companyName}\n'
        '${VendorInfo.phoneDisplay}\n'
        'ایمیل: ${VendorInfo.email}';
  }
}
