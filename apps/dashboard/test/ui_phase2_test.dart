/// تست‌های فاز ۲ و UI — گارانتی، پیش‌بینی، پیکربندی تم، جدول پیشرفته
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/forecast_service.dart';
import 'package:jsh_service_dashboard/core/theme/theme_config.dart';
import 'package:jsh_service_dashboard/core/warranty.dart';
import 'package:jsh_service_dashboard/features/board/board.dart';
import 'package:jsh_service_dashboard/core/utils.dart';
import 'package:jsh_service_dashboard/shared/widgets/data_table_pro.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String base;
  late final String supportPath = '$base/support';
  late final String docsPath = '$base/docs';
  _FakePathProvider(this.base);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_ui_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('۱) گارانتی: ساخت در تحویل، وضعیت پویا و تمدید', () async {
    final c = Customer(name: 'مهدی نیکو', phone: '09132223344');
    c.id = await CustomerRepo.insert(c);
    final d = Device(customerId: c.id!, model: 'PS5');
    d.id = await DeviceRepo.insert(d);
    final t = Ticket(
      code: await TicketRepo.nextCode(),
      customerId: c.id!,
      deviceId: d.id!,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now(),
      dueTime: '18:00',
      defect: 'روشن نمی‌شود',
      estimateAmount: 900000,
      depositAmount: 200000,
      accessories: [],
      termsAccepted: true,
    );
    t.id = await TicketRepo.insert(t);

    expect(await WarrantyRepo.forTicket(t.id!), isNull);
    await WarrantyRepo.upsertForTicket(t.id!, 6);
    final w = (await WarrantyRepo.forTicket(t.id!))!;
    expect(w.months, 6);
    expect(w.liveStatus(), anyOf('active', 'expiring'));
    await WarrantyRepo.extend(t.id!, 12);
    final w2 = (await WarrantyRepo.forTicket(t.id!))!;
    expect(w2.months, 18);
    expect(w2.endDate.isAfter(w.endDate), isTrue);
  });

  test('۲) پیش‌بینی: میانگین متحرک صادقانه + آمار گارانتی', () async {
    final past = await ForecastService.monthlyRevenue();
    expect(past.length, 6);
    final future = await ForecastService.forecast(months: 3);
    expect(future.length, 3);
    for (final f in future) {
      expect(f.isForecast, isTrue);
    }
    final avg = past.fold<double>(0, (s, e) => s + e.value) / past.length;
    expect(future.first.value, closeTo(avg, 1));
    final wstats = await ForecastService.warrantyStats();
    expect(wstats.active + wstats.expiring + wstats.expired,
        greaterThanOrEqualTo(1));
  });

  test('۳) پیکربندی تم: سه پیش‌فرض، شخصی‌سازی و پایدارسازی', () async {
    final cfg = ThemeConfig(
        preset: 'creamGold',
        accentHex: 'D4A437',
        radiusScale: 1.4,
        fontScale: 1.1,
        density: 1.2,
        shrinkToFit: true);
    await ThemeConfig.save(cfg);
    final raw = await SettingsRepo.get('theme_config');
    expect(raw, isNotEmpty);
    final loaded =
        ThemeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(loaded.preset, 'creamGold');
    expect(loaded.accentHex, 'D4A437');
    expect(loaded.palette.primary, const Color(0xFFD4A437));
    for (final preset in ThemePreset.values) {
      final t = AppTheme.build(ThemeConfig(preset: preset.key));
      expect(t.scaffoldBackgroundColor, isNotNull);
      expect(t.textTheme.bodyMedium, isNotNull);
    }
  });

  testWidgets('۴) جدول پیشرفته: سورت و جمع پویا', (tester) async {
    final rows = [
      for (var i = 1; i <= 6; i++) _DemoRow('R-$i', i * 100),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: DataTablePro<_DemoRow>(
                tableId: 'demo_test',
                rows: rows,
                columns: [
                  ProColumn<_DemoRow>(
                      label: 'کد', display: (r) => r.code, width: 120),
                  ProColumn<_DemoRow>(
                      label: 'مبلغ',
                      display: (r) => toPersianDigits('${r.amount}'),
                      width: 120,
                      numeric: (r) => r.amount),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('R-1'), findsOneWidget);
    expect(find.textContaining('جمع'), findsWidgets);

    await tester.tap(find.text('مبلغ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مبلغ'));
    await tester.pumpAndSettle();
    expect(find.text('R-6'), findsOneWidget);
  });

  testWidgets('۵) کارتابل: ویجت واقعی رندر می‌شود', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: BoardPage()),
        ),
      ),
    );
    // فاز ۳ — لودینگ با I/O واقعی: تناوب runAsync/pump تا پایان لودینگ
    await tester.pump(const Duration(milliseconds: 100));
    for (var k = 0; k < 25; k++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('کارتابل تعمیرات'), findsOneWidget);
    // باز کردن درخت — جلوگیری از تایمر معلق در پایان تست
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}

class _DemoRow {
  final String code;
  final int amount;
  _DemoRow(this.code, this.amount);
}
