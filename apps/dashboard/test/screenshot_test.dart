/// اسکرین‌شات هر بخش × هر تم — رندر واقعی ویجت‌های برنامه با موتور Flutter
/// خروجی در docs/screenshots مخزن گیت‌هاب ذخیره می‌شود؛ نسخه محلی پس از پوش حذف می‌شود.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/constants.dart';
import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/reminder_service.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/theme/theme_config.dart';
import 'package:jsh_service_dashboard/core/warranty.dart';
import 'package:jsh_service_dashboard/features/assistant/assistant_page.dart';
import 'package:jsh_service_dashboard/features/board/board.dart';
import 'package:jsh_service_dashboard/features/calendar/calendar_page.dart';
import 'package:jsh_service_dashboard/features/customers/customers.dart';
import 'package:jsh_service_dashboard/features/home/dashboard.dart';
import 'package:jsh_service_dashboard/features/invoices/invoices.dart';
import 'package:jsh_service_dashboard/features/reminders/reminders.dart';
import 'package:jsh_service_dashboard/features/settings/theme_settings.dart';
import 'package:jsh_service_dashboard/features/warranty/warranty_page.dart';

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

/// داده نمایشی واقعی از مسیر مخازن برنامه (برای صحنه‌های پر و زیبا)
Future<void> _seedDemoData() async {
  final names = [
    ('علی رضایی', '09131110001', 'iPhone 13', 'تصویر نمی‌آید'),
    ('مهدی نیکو', '09131110002', 'PS5', 'روشن نمی‌شود'),
    ('زهرا محمدی', '09131110003', 'لپ‌تاپ Lenovo', 'باتری نگه نمی‌دارد'),
    ('حسین کریمی', '09131110004', 'Xbox Series X', 'دیسک نمی‌خواند'),
    ('سارا احمدی', '09131110005', 'MacBook Air', 'صفحه خط دارد'),
    ('رضا موسوی', '09131110006', 'گوشی Samsung S22', 'شحنه خالی می‌ماند'),
    ('فاطمه حسینی', '09131110007', 'تبلت Huawei', 'شارژ نمی‌شود'),
    ('امیر قاسمی', '09131110008', 'مانیتور LG', 'پیکسل سوخته'),
    ('نگار صادقی', '09131110009', 'ایربادز', 'صدای یک طرف'),
    ('کاوه رستمی', '09131110010', 'Yamaha Receiver', 'کانال راست قطع'),
  ];
  final statuses = [
    TicketStatus.intake,
    TicketStatus.diagnosis,
    TicketStatus.waitingPart,
    TicketStatus.repairing,
    TicketStatus.testing,
    TicketStatus.ready,
    TicketStatus.delivered,
    TicketStatus.repairing,
    TicketStatus.ready,
    TicketStatus.delivered,
  ];

  for (var i = 0; i < names.length; i++) {
    final (name, phone, model, defect) = names[i];
    final c = Customer(
        name: name,
        phone: phone,
        nationalId: '12345678${i.toString().padLeft(2, '0')}',
        tag: i % 3 == 0 ? 'VIP' : (i % 3 == 1 ? 'عادی' : 'عمده'));
    c.id = await CustomerRepo.insert(c);
    final d = Device(customerId: c.id!, model: model);
    d.id = await DeviceRepo.insert(d);
    final t = Ticket(
      code: await TicketRepo.nextCode(),
      customerId: c.id!,
      deviceId: d.id!,
      intakeDate: DateTime.now().subtract(Duration(days: 12 - i)),
      dueDate: DateTime.now().add(Duration(days: i - 2)),
      dueTime: '18:00',
      defect: defect,
      estimateAmount: 400000 + i * 150000,
      depositAmount: i == 0 ? 0 : 100000 + i * 50000,
      accessories: ['درب پشت', if (i % 2 == 0) 'شارژر'],
      termsAccepted: true,
    );
    t.id = await TicketRepo.insert(t);
    // اقلام و پرداخت برای فاکتورها و نمودارها
    await TicketItemRepo.insert(TicketItem(
      ticketId: t.id!,
      description: i % 2 == 0 ? 'قطعه اصلی' : 'خدمات فنی',
      qty: 1 + (i % 3),
      price: 150000 + i * 90000,
    ));
    if (t.depositAmount > 0) {
      await PaymentRepo.insert(Payment(
          ticketId: t.id!, amount: t.depositAmount, kind: 'deposit'));
    }
    if (i % 4 == 3) {
      await PaymentRepo.insert(Payment(
          ticketId: t.id!, amount: 300000, kind: 'remaining'));
    }
    // وضعیت‌های متنوع برای کارتابل و دونات
    final targetIdx = statuses[i];
    final curIdx = TicketStatus.order.indexOf(t.status);
    for (var s = curIdx; s < TicketStatus.order.indexOf(targetIdx); s++) {
      await TicketRepo.changeStatus(t.id!, TicketStatus.order[s + 1]);
    }
    // گارانتی برای تحویل‌شده‌ها
    if (statuses[i] == TicketStatus.delivered) {
      await WarrantyRepo.upsertForTicket(t.id!, 6);
    }
    // یادآوری
    await ReminderService.ensureForTicket(t, 3, 9);
  }
}

Future<void> _loadPersianFont() async {
  final regular = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf');
  final loader = FontLoader('Vazirmatn')
    ..addFont(Future.value(regular))
    ..addFont(Future.value(bold));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_shots');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    await _loadPersianFont();
    await _seedDemoData();
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  final pages = <(String, Widget Function(AppSession))>[
    ('dashboard', (s) => DashboardPage(session: s, onGo: (_) {})),
    ('board', (s) => BoardPage()),
    ('invoices', (s) => InvoicesPage()),
    ('calendar', (s) => CalendarPage()),
    ('customers', (s) => CustomersPage()),
    ('reminders', (s) => RemindersPage()),
    ('assistant', (s) => AssistantPage()),
    ('warranty', (s) => WarrantyPage()),
    ('theme_settings', (s) => ThemeSettingsPage()),
  ];

  for (final preset in ThemePreset.values) {
    for (final (pageName, makePage) in pages) {
      testWidgets('${preset.key}_$pageName', (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final cfg =
            ThemeConfig.notifier.value.copyWith(preset: preset.key);
        ThemeConfig.notifier.value = cfg;

        await tester.pumpWidget(
          MaterialApp(
            title: 'JSH',
            debugShowCheckedModeBanner: false,
            locale: const Locale('fa', 'IR'),
            theme: AppTheme.build(cfg),
            builder: (context, child) => AppThemeScope(
              notifier: ThemeConfig.notifier,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: Scaffold(
              appBar: AppBar(
                title: Text(
                    'JSH Service Dashboard — ${preset.labelFa}'),
              ),
              body: makePage(AppSession.I),
            ),
          ),
        );
        // پمپ مشخص — برخی صفحات با انیمیشن مداوم هرگز settle نمی‌شوند
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../docs/screenshots/${preset.key}_$pageName.png'),
        );
      });
    }
  }
}
