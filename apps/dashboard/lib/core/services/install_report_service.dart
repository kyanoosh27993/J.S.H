/// سرویس گزارش نصب الزامی (N-03) — قلب قفل تجاری
/// پس از نصب، گزارش کامل فعال‌سازی در یک فایل محلی روی دستگاه ثبت می‌شود:
/// چه خریداری، چه تاریخی، چه دستگاهی با چه مشخصات سخت‌افزاری، نصب چندم و باقیمانده.
/// (نسخه 0.5.0: ارسال ایمیلی حذف شد — گزارش فقط محلی است)
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../repos.dart';
import 'license_service.dart';

enum GateState {
  ok, // گزارش ثبت شده — اجرای عادی
  waitingConsent, // ویزارد اول باید تکمیل شود
  queueing, // گزارش در صف است و اینترنت هنوز نیامده — بستن راه‌اندازی
  deadlinePassed, // بیش از ۳۰ روز بدون ارسال — پیام اتصال و ثبت ایمیل معتبر
}

class InstallReportService {

  /// جمع‌آوری مشخصات سخت‌افزاری دستگاه
  static Future<String> collectHardware() async {
    final lines = <String>[];
    lines.add('سیستم‌عامل: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    lines.add('نام رایانه: ${Platform.localHostname}');
    if (Platform.isWindows) {
      lines.add('پردازنده: ${await _cmd('wmic', ['cpu', 'get', 'Name'])}');
      lines.add('حافظه کل: ${await _cmd('wmic', ['ComputerSystem', 'get', 'TotalPhysicalMemory'])}');
      lines.add('دیسک: ${await _cmd('wmic', ['diskdrive', 'get', 'Model'])}');
    } else {
      try {
        final mem = await Process.run('free', ['-m']);
        lines.add('حافظه: ${mem.stdout.toString().split('\n').skip(1).first.trim()}');
      } catch (_) {}
    }
    lines.add('اثر انگشت لایسنس: ${await LicenseService.fingerprint()}');
    lines.add('زمان جمع‌آوری: ${DateTime.now().toIso8601String()}');
    return lines.join('\n');
  }

  static Future<String> _cmd(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args);
      final lines = r.stdout
          .toString()
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && !e.toLowerCase().contains(cmd))
          .toList();
      return lines.isNotEmpty ? lines.first : 'نامشخص';
    } catch (_) {
      return 'نامشخص';
    }
  }

  /// ساخت متن گزارش و ذخیره محلی آن (نسخه 0.5.0 — بدون ایمیل)
  static Future<String> writeReport({
    required String buyerName,
    required String userEmail,
    required int installCount,
    required String hardwareReport,
  }) async {
    final remaining = AppInfo.maxInstalls - installCount;
    final now = DateTime.now();
    final body = 'گزارش نصب برنامه «داشبورد تعمیرات و خدمات»\n\n'
        'نام خریدار: $buyerName\n'
        'ایمیل ثبت‌شده خریدار: $userEmail\n'
        'تاریخ نصب: ${now.toIso8601String()}\n'
        'شماره نصب فعلی: $installCount از ${AppInfo.maxInstalls}\n'
        'نصب باقیمانده مجاز: ${remaining < 0 ? 0 : remaining}\n\n'
        'مشخصات دستگاه و سخت‌افزار:\n$hardwareReport\n\n'
        'پروژه: ${AppInfo.projectId} — نسخه: ${AppInfo.version}\n'
        'این گزارش به‌صورت خودکار توسط برنامه ثبت شده است (نیازمندی N-03).';

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/install_reports');
    await dir.create(recursive: true);
    final f = File('${dir.path}/install_report_$installCount.txt');
    await f.writeAsString(body, flush: true);
    return f.path;
  }

  /// تشخیص وضعیت دروازه راه‌اندازی
  static GateState evaluateGate({
    required bool consented,
    required String userEmail,
    required bool reportSent,
    required String firstRunAt,
    required int pendingReportAttempts,
  }) {
    if (!consented || userEmail.trim().isEmpty) return GateState.waitingConsent;
    if (reportSent) return GateState.ok;
    final first = DateTime.tryParse(firstRunAt) ?? DateTime.now();
    final days = DateTime.now().difference(first).inDays;
    // بعد از ۳۰ روز بدون ارسال: پیام «اتصال اینترنت + ثبت ایمیل واقعی» (N-03)
    if (days > AppInfo.reportDeadlineDays) return GateState.deadlinePassed;
    return GateState.queueing;
  }

  /// اثر انگشت کوتاه برای نمایش در ویزارد
  static String shortHash(String s) =>
      md5.convert(utf8.encode(s)).toString().substring(0, 8).toUpperCase();
}
