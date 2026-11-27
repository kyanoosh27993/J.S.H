/// تست‌های فاز ۲ نقشه راه نسخه ۳ — شمسی‌سازی و ورودی مبلغ
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';

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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase2_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    await AppSession.I.loginWith('admin', 'admin');
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('بند ۱۲ نسخه ۳ — شماره رسید شمسی', () {
    test('پیشوند RCP بر اساس سال/ماه/روز شمسی است', () async {
      final code = await TicketRepo.nextCode();
      final m = RegExp(r'^RCP-(\d{8})-(\d{3,})$').firstMatch(code);
      expect(m, isNotNull);
      final ymd = m!.group(1)!;
      final y = int.parse(ymd.substring(0, 4));
      final mo = int.parse(ymd.substring(4, 6));
      final d = int.parse(ymd.substring(6, 8));
      // سال شمسی جاری باید ۱۴۰۴ تا ۱۴۰۶ باشد (بازه تست سال ۲۰۲۵-۲۰۲۷)
      expect(y, inInclusiveRange(1404, 1406));
      expect(mo, inInclusiveRange(1, 12));
      expect(d, inInclusiveRange(1, 31));
    });
  });
}
