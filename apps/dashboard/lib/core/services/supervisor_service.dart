/// اکانت سوپروایزر — قاعده ۹ و ۱۲
/// رمز در سورس فقط به‌صورت SHA-256 با نمک ثابت برنامه ذخیره می‌شود؛
/// حالت سوپروایزر فقط در حافظه نشست است و هر عملیت آن در audit_log ثبت می‌شود.
/// ضد دستکاری لایسنس: HMAC رکورد لایسنس — ویرایش دستی بانک قفل برنامه را فعال می‌کند.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/db.dart';
import '../repos.dart';

class SupervisorService {
  // رمز خام هرگز در سورس نیست — فقط هش SHA-256(نمک + رمز)
  static const String _salt = 'JSH::AVRIN_SEGAL::SUPER::1405';
  static const String _hash =
      'f3fd4187aff99a5c7110f3e6bc4149e45e87ae4c00816c0d33091ec6a2b1290f';

  // قفل تلاش‌های ناموفق — فقط در حافظه نشست
  static int _fails = 0;
  static DateTime? _lockedUntil;

  static bool _active = false;
  static bool get active => _active;
  static bool get isLockedNow =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
  static int get failCount => _fails;

  static Future<bool> login(String password) async {
    if (isLockedNow) return false;
    final h = sha256.convert(utf8.encode(_salt + password)).toString();
    if (h == _hash) {
      _active = true;
      _fails = 0;
      await AuditRepo.log(
          'supervisor_login', 'ورود سوپروایزر — ${DateTime.now().toIso8601String()}');
      return true;
    }
    _fails++;
    if (_fails >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(minutes: 5));
      await AuditRepo.log(
          'supervisor_lockout', '۵ تلاش ناموفق ورود سوپروایزر — قفل ۵ دقیقه');
    }
    await AuditRepo.log('supervisor_fail', 'تلاش ناموفق #$_fails');
    return false;
  }

  static void logout() {
    _active = false;
  }
}

/// ثبت رویدادهای حساس امنیتی
class AuditRepo {
  static Future<void> log(String action, String detail) async {
    try {
      final db = await Db.instance();
      await db.insert('audit_log', {
        'action': action,
        'detail': detail,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<List<Map<String, Object?>>> recent({int limit = 100}) async {
    final db = await Db.instance();
    return db.query('audit_log', orderBy: 'id DESC', limit: limit);
  }
}

/// ضد دستکاری لایسنس (F-09):
/// کلید HMAC = نمک ثابت برنامه + اثر انگشت دستگاه.
/// کپی بانک روی دستگاه دیگر یا ویرایش دستی رکورد، ناهم‌خوانی HMAC می‌دهد
/// و برنامه با پیام «دستکاری» قفل می‌شود. بازگشایی فقط با پشتیبانی سازنده.
class LicenseIntegrity {
  static List<int> _key(String fingerprint) =>
      utf8.encode('$saltPrefix|HMAC|$fingerprint');

  static const String saltPrefix = 'JSH::AVRIN_SEGAL::LICENSE';

  static String compute(String fingerprint, Map<String, Object?> row) {
    final payload = [
      row['fingerprint'] ?? '',
      row['install_count'] ?? 0,
      row['user_email'] ?? '',
      row['buyer_name'] ?? '',
      row['consented_at'] ?? '',
      row['report_status'] ?? '',
      row['first_run_at'] ?? '',
    ].join('|');
    return Hmac(sha256, _key(fingerprint))
        .convert(utf8.encode(payload))
        .toString();
  }

  /// نوشتن امضای صحیح — بعد از هر تغییر معتبر لایسنس (فعال‌سازی، افزایش شمارنده)
  static Future<void> write() async {
    try {
      final db = await Db.instance();
      final rows = await db.query('license_state', limit: 1);
      if (rows.isEmpty) return;
      await SettingsRepo.set(
          'license_hmac', compute(_fpFrom(rows.first), rows.first));
    } catch (_) {}
  }

  static String _fpFrom(Map<String, Object?> row) =>
      (row['fingerprint'] ?? '') as String;

  /// بررسی سلامت — بعد از هر شروع برنامه
  /// خروجی: true یعنی سالم یا امضا ثبت نشده (نصب تازه)
  static Future<LicenseIntegrityResult> verify() async {
    try {
      final db = await Db.instance();
      final rows = await db.query('license_state', limit: 1);
      if (rows.isEmpty) return LicenseIntegrityResult.ok;
      final stored = await SettingsRepo.get('license_hmac');
      if (stored.isEmpty) return LicenseIntegrityResult.ok; // نصب تازه
      final fp = _fpFrom(rows.first);
      final expected = compute(fp, rows.first);
      if (stored != expected) return LicenseIntegrityResult.tampered;
      // بررسی ثابت‌بودن شمارنده نسبت به ذخیره‌های خارج از بانک
      final external =
          int.tryParse(await SettingsRepo.get('install_count_mirror')) ?? 0;
      final dbCount = (rows.first['install_count'] ?? 0) as int;
      if (dbCount < external) return LicenseIntegrityResult.rolledBack;
      return LicenseIntegrityResult.ok;
    } catch (_) {
      return LicenseIntegrityResult.ok;
    }
  }

  /// ذخیره آینه شمارنده خارج از رکورد لایسنس
  static Future<void> mirrorCount(int count) async {
    await SettingsRepo.set('install_count_mirror', '$count');
  }
}

enum LicenseIntegrityResult { ok, tampered, rolledBack }
