/// تست فعال‌سازی با کد دستگاه‌محور — فاز ۱ نقشه راه نسخه ۲
/// پوشش: وضعیت اولیه، نگهبان تاریخ، کد اشتباه/دستگاه دیگر، کد معتبر، انقضا، پایداری در بانک
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:activation_core/activation_core.dart';
import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/activation_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String base;
  _FakePathProvider(this.base);
  @override
  Future<String?> getApplicationSupportPath() async => '$base/support';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$base/docs';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String tempBase;

  setUpAll(() async {
    final t = await DirectoryTemp.create();
    tempBase = t;
    PathProviderPlatform.instance = _FakePathProvider(tempBase);
    // فایل پنهان نگهبان تاریخ بین اجراهای تست مشترک است — پاک‌سازی
    try {
      final home = Platform.environment['HOME'] ?? '.';
      final guard = File('$home/.config/jsh/.activation_guard');
      if (await guard.exists()) await guard.delete();
    } catch (_) {}
    await Db.instance();
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      final home = Platform.environment['HOME'] ?? '.';
      final guard = File('$home/.config/jsh/.activation_guard');
      if (await guard.exists()) await guard.delete();
    } catch (_) {}
  });

  final deviceId = 'testdevicefingerprint0000000000000000aa';
  final today = DateTime(2026, 11, 27, 12);

  LicenseState fresh() {
    final s = LicenseState();
    s.fingerprint = deviceId;
    return s;
  }

  test('۱) وضعیت اولیه: فعال‌سازی نشده', () async {
    final s = fresh();
    expect(await ActivationService.statusOf(s, now: today),
        ActivationStatus.notActivated);
  });

  test('۲) نگهبان تاریخ: روز اول ذخیره می‌شود', () async {
    final s = fresh();
    final lastSeen = await ActivationService.clockGuard(s, now: today);
    expect(lastSeen, isNull); // روز اول — هیچ lastSeen قبلی نبود
    expect(s.lastSeenDate, isNotEmpty);
  });

  test('۳) کد فعال‌سازی معتبر برنامه را فعال می‌کند', () async {
    final s = fresh();
    final code = ActivationCodec.generate(
      expiry: DateTime.utc(2027, 11, 27),
      deviceId: deviceId,
      maxReinstalls: 3,
    );
    final err = await ActivationService.activate(s, code, now: today);
    expect(err, isNull, reason: 'انتظار فعال‌سازی موفق: $err');
    expect(s.activated, isTrue);
    expect(s.activationExpiry, isNotEmpty);
    expect(await ActivationService.statusOf(s, now: today),
        ActivationStatus.active);
  });

  test('۴) کد دستگاه دیگر پذیرفته نمی‌شود', () async {
    final s = fresh();
    final otherCode = ActivationCodec.generate(
      expiry: DateTime.utc(2027, 11, 27),
      deviceId: 'other-device-fingerprint-aaaaaaaaaaaaaaaa',
    );
    final err = await ActivationService.activate(s, otherCode, now: today);
    expect(err, isNotNull);
    expect(err, contains('دستگاه دیگری'));
  });

  test('۵) کد منقضی رد می‌شود', () async {
    final s = fresh();
    final expiredCode = ActivationCodec.generate(
      expiry: DateTime.utc(2026, 1, 1),
      deviceId: deviceId,
    );
    final err = await ActivationService.activate(s, expiredCode, now: today);
    expect(err, isNotNull);
    expect(err, contains('به پایان رسیده'));
  });

  test('۶) ارقام فارسی کد نرمال می‌شود', () async {
    final s = fresh();
    final code = ActivationCodec.generate(
        expiry: DateTime.utc(2027, 11, 27), deviceId: deviceId);
    final faCode = code
        .replaceAll('0', '۰')
        .replaceAll('1', '۱')
        .replaceAll('2', '۲');
    final err = await ActivationService.activate(s, faCode, now: today);
    expect(err, isNull, reason: 'کد با ارقام فارسی هم باید پذیرفته شود');
  });

  test('۷) روزهای باقیمانده و پیام هشدار ۷ روز (بند ۱۸)', () async {
    final s = fresh();
    final code = ActivationCodec.generate(
        expiry: DateTime(2026, 12, 3), deviceId: deviceId);
    await ActivationService.activate(s, code, now: today);
    // ۲۷ نوامبر تا ۳ دسامبر = ۶ روز
    expect(ActivationService.remainingDays(s, now: today), 6);
    final msg = ActivationService.expiryWarningMessage(6);
    expect(msg, contains('۶ روز'));
    expect(msg, contains('۰۹۱۳۰۳۵۶۲۵۰'));
  });

  test('۸) فعال‌سازی در بانک پایدار می‌ماند و مجدد بارگذاری می‌شود', () async {
    final s = fresh();
    final code = ActivationCodec.generate(
        expiry: DateTime.utc(2027, 11, 27), deviceId: deviceId);
    await ActivationService.activate(s, code, now: today);
    final reloaded = await LicenseRepo.load();
    expect(reloaded.activationCode, code);
    expect(await ActivationService.statusOf(reloaded, now: today),
        ActivationStatus.active);
  });
}

/// پوشه موقت — نام کوتاه برای خوانایی تست
class DirectoryTemp {
  static Future<String> create() async =>
      (await Directory.systemTemp.createTemp('jsh_activation')).path;
}
