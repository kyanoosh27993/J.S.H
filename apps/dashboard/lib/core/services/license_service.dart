/// سرویس لایسنس تجاری (F-09) — اثر انگشت سخت‌افزار + شمارنده نصب
/// فقط روی یک رایانه؛ حداکثر ۳ بار نصب؛ بار چهارم پیام تماس با پشتیبانی.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../constants.dart';
import '../utils.dart';

class LicenseLockedException implements Exception {
  final int installCount;
  LicenseLockedException(this.installCount);
  @override
  String toString() => 'LICENSE_LOCKED';
}

class LicenseService {
  /// اثر انگشت سخت‌افزار: ترکیب شناسه‌های ثابت سیستم + هش SHA-256
  static Future<String> fingerprint() async {
    final parts = <String>[];
    if (Platform.isWindows) {
      parts.add(await _winReg(
          r'HKLM\SOFTWARE\Microsoft\Cryptography', 'MachineGuid'));
      parts.add(await _winCommand('wmic', ['cpu', 'get', 'ProcessorId']));
      parts.add(await _winCommand(
          'wmic', ['baseboard', 'get', 'SerialNumber']));
      parts.add(Platform.localHostname);
    } else {
      parts.add(await _readIfExists('/etc/machine-id'));
      parts.add(Platform.localHostname);
      parts.add(Platform.operatingSystemVersion);
    }
    final joined = parts.where((e) => e.trim().isNotEmpty).join('|');
    return sha256.convert(utf8.encode(joined)).toString().substring(0, 32);
  }

  static Future<String> _readIfExists(String path) async {
    try {
      final f = File(path);
      return await f.exists() ? (await f.readAsString()).trim() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _winReg(String key, String value) async {
    try {
      final r = await Process.run('reg', ['query', key, '/v', value]);
      if (r.exitCode != 0) return '';
      final m =
          RegExp(r'REG_SZ\s+(\S+)').firstMatch(r.stdout.toString());
      return m?.group(1) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _winCommand(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args);
      if (r.exitCode != 0) return '';
      final lines = r.stdout
          .toString()
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && !e.toLowerCase().startsWith(cmd))
          .toList();
      return lines.isNotEmpty ? lines.first : '';
    } catch (_) {
      return '';
    }
  }

  /// خواندن شمارنده نصب از چند مکان مستقل؛ بیشینه معتبر است (ضد کپی ساده)
  static Future<int> readInstallCount() async {
    var best = 0;
    for (final v in await _allCounters()) {
      if (v > best) best = v;
    }
    return best;
  }

  static Future<List<int>> _allCounters() async {
    final out = <int>[];
    // ۱) فایل پنهان در ProgramData (ویندوز) یا config (سایر)
    try {
      final f1 = File(await _hiddenStorePath());
      if (await f1.exists()) {
        final j = jsonDecode(await f1.readAsString());
        out.add((j['install_count'] ?? 0) as int);
      }
    } catch (_) {}
    // ۲) رجیستری ویندوز
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
            'reg', ['query', r'HKCU\Software\JSH\License', '/v', 'InstallCount']);
        if (r.exitCode == 0) {
          final m = RegExp(r'0x([0-9a-fA-F]+)')
              .allMatches(r.stdout.toString())
              .toList();
          if (m.isNotEmpty) {
            out.add(int.parse(m.last.group(1)!, radix: 16));
          }
        }
      } catch (_) {}
    }
    // ۳) رکورد پایگاه‌داده — توسط فراخواننده جداگانه خوانده می‌شود
    return out;
  }

  static Future<String> _hiddenStorePath() async {
    if (Platform.isWindows) {
      final pd = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
      return '$pd\\JSH\\.license_store';
    }
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.config/jsh/.license_store';
  }

  /// ثبت/افزایش شمارنده در همه مکان‌ها + برچسب پنهانی
  static Future<void> writeInstallCount(int count, String fingerprint) async {
    final path = await _hiddenStorePath();
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({
      'install_count': count,
      'fingerprint': fingerprint,
      'updated_at': DateTime.now().toIso8601String(),
    }));
    if (Platform.isWindows) {
      try {
        await Process.run(
            'attrib', ['+h', path]);
      } catch (_) {}
      try {
        await Process.run('reg', [
          'add', r'HKCU\Software\JSH\License', '/v', 'InstallCount',
          '/t', 'REG_DWORD', '/d', count.toString(), '/f',
        ]);
      } catch (_) {}
    }
  }

  /// گام‌های شروع: اگر شمارنده از حد گذشته باشد، قفل کامل
  static Future<void> guard(int dbInstallCount) async {
    if (dbInstallCount > AppInfo.maxInstalls) {
      throw LicenseLockedException(dbInstallCount);
    }
  }

  static String lockMessage(int installCount) {
    final remain = AppInfo.maxInstalls - installCount + 1;
    final maxFa = toPersianDigits('${AppInfo.maxInstalls}');
    return 'این نسخه از برنامه قبلاً ${toPersianDigits('$installCount')} بار روی این رایانه نصب شده است و سهمیه نصب '
        '($maxFa بار) به پایان رسیده است.\n'
        'برای نصب دوباره باید با پشتیبانی برنامه تماس بگیرید.\n'
        '${VendorInfo.companyName} — ${VendorInfo.phoneDisplay}\n'
        'ایمیل پشتیبانی: ${VendorInfo.email}\n'
        'پاسخ پشتیبانی: ${toPersianDigits('$remain')} نصب باقی‌مانده قبلاً ثبت شده و قفل فعال شده است.';
  }
}
