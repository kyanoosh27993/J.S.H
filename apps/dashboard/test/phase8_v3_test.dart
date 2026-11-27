/// تست‌های فاز ۸ — بند ۰ (مسیر پرتابل دیتابیس) و بند ۳ (ضد عقب‌بردن تاریخ)
///   • بند ۳: اگر last_seen_date آینده باشد و امروز عقب‌تر بیفتد → تشخیص
///     دستکاری تاریخ (ClockTamperedException) — حتی اگر رکورد لایسنس پاک شود،
///     آینه settings جلوی کار را می‌گیرد.
///   • بند ۳: اختلاف یک‌روزه (منطقه زمانی) تحمل می‌شود — grace ۳۰ ساعت.
///   • بند ۰: وجود portable.marker کنار exe → resolveBaseDir همان پوشه
///     را برمی‌گرداند؛ بدون نشانگر → ApplicationSupport (رفتار قبلی).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/activation_service.dart';
import 'package:jsh_service_dashboard/core/services/install_paths.dart';

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
  late Directory tempDir;
  late Directory fakeExeDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase8_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
  });

  tearDown(() async {
    // مهم: override تستی مسیر exe هرگز نباید به تست بعدی نشت کند
    InstallPaths.debugExeDir = null;
  });

  tearDownAll(() async {
    await Db.reset();
    InstallPaths.debugExeDir = null;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('بند ۳ — نگهبان عقب‌بردن تاریخ سیستم', () {
    test('last_seen_date ۳ روز جلوتر + امروز امروز → ClockTamperedException (دستکاری)',
        () async {
      final today = DateTime.now();
      // بازگشت تا ۳۰ ساعت (جابه‌جایی منطقه زمانی) طبق طراحی تحمل می‌شود؛
      // بازگشت ۳ روزه قطعاً خارج از گریس است و باید قفل شود
      final tomorrow =
          DateTime(today.year, today.month, today.day + 3);
      final state = LicenseState();
      state.lastSeenDate = tomorrow.toIso8601String();
      await SettingsRepo.set('last_seen_mirror', state.lastSeenDate);
      // امروز عقب‌تر از آخرین اجرا = عقب‌بردن تاریخ → قفل
      expect(
        () => ActivationService.clockGuard(state, now: today),
        throwsA(isA<ClockTamperedException>()),
      );
    });

    test('حتی با پاک‌شدن رکورد، آینه settings دستکاری را می‌گیرد (قاعده ۱۲)',
        () async {
      final today = DateTime.now();
      final state = LicenseState();
      state.lastSeenDate = '';
      // رکورد خالی اما آینه خارج از بانک ۳ روز جلوتر را دیده است (خارج از گریس)
      await SettingsRepo.set(
          'last_seen_mirror',
          DateTime(today.year, today.month, today.day + 3)
              .toIso8601String());
      expect(
        () => ActivationService.clockGuard(state, now: today),
        throwsA(isA<ClockTamperedException>()),
      );
    });

    test('اختلاف یک روز (grace منطقه زمانی) قفل نمی‌شود', () async {
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);
      final yesterday =
          DateTime(today.year, today.month, today.day).subtract(
        const Duration(days: 1),
      );
      final state = LicenseState();
      // آخرین اجرا امروز؛ تاریخ سیستم یک روز عقب — در تحمل ۳۰ ساعت است
      state.lastSeenDate = todayDay.toIso8601String();
      await SettingsRepo.set('last_seen_mirror', state.lastSeenDate);
      final seen =
          await ActivationService.clockGuard(state, now: yesterday);
      expect(seen, isNotNull); // قفل نشد؛ lastSeen برگردانده شد
      // و به‌روزرسانی فقط به جلو انجام می‌شود → رکورد هنوز همان امروز است
      expect(state.lastSeenDate, todayDay.toIso8601String());
    });

    test('اجرای طبیعی همان روز، lastSeen را جلو می‌برد', () async {
      final now = DateTime.now();
      final state = LicenseState();
      state.lastSeenDate = '';
      await SettingsRepo.set('last_seen_mirror', '');
      // خروجی seen به فایل پنهان خارج از بانک هم بستگی دارد (قاعده ۱۲) —
      // پس مقدار دقیق آن را چک نمی‌کنیم؛ فقط به‌روزرسانی رکورد مهم است
      await ActivationService.clockGuard(state, now: now);
      expect(
        state.lastSeenDate,
        DateTime(now.year, now.month, now.day).toIso8601String(),
      );
    });
  });

  group('بند ۰ — resolveBaseDir با نشانگر پرتابل', () {
    test('با portable.marker کنار exe → پوشه نصب برگردانده می‌شود', () async {
      fakeExeDir = Directory('${tempDir.path}${Platform.pathSeparator}installdir');
      await fakeExeDir.create(recursive: true);
      InstallPaths.debugExeDir = fakeExeDir.path;
      // بدون نشانگر → هنوز ApplicationSupport
      expect(await InstallPaths.isPortable(), isFalse);
      expect(await InstallPaths.resolveBaseDir(),
          '${tempDir.path}${Platform.pathSeparator}support');
      // نشانگر را می‌نویسیم (همان کاری که نصب‌کننده در CurStepChanged می‌کند)
      await File(
              '${fakeExeDir.path}${Platform.pathSeparator}portable.marker')
          .writeAsString('JSH portable install');
      expect(await InstallPaths.isPortable(), isTrue);
      expect(await InstallPaths.resolveBaseDir(), fakeExeDir.path);
      // dbPath هم باید از همان پوشه پیروی کند
      expect(
        (await Db.dbPath()).startsWith(fakeExeDir.path),
        isTrue,
      );
    });

    test('بدون نشانگر → رفتار قبلی (ApplicationSupport) حفظ می‌شود',
        () async {
      InstallPaths.debugExeDir = null;
      expect(await InstallPaths.isPortable(), isFalse);
      expect(await InstallPaths.resolveBaseDir(),
          '${tempDir.path}${Platform.pathSeparator}support');
    });
  });
}
