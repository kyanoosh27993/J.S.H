/// تست‌های فاز ۷ نسخه ۳ — بند ۱۶ (موتور نیت دستیار هوشمند) + بند ۱۴.۸۶ (فلش‌های RTL)
/// توابع خالص نرمال‌سازی، استخراج تاریخ و تشخیص نیت + یک تست دیتابیسی یادآوری‌های امروز
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/auth_service.dart';
import 'package:jsh_service_dashboard/core/services/assistant_service.dart';
import 'package:jsh_service_dashboard/core/utils.dart';
import 'package:jsh_service_dashboard/shared/widgets/shamsi_calendar.dart';

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
  late int adminId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase7_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    final admin = await UserRepo.byUsernameRow('admin');
    adminId = admin!['id'] as int;
    await AppSession.I.loginWith('admin', 'admin');

    // سفارش موعد امروز ساعت ۹ — برای تست «یادآوری‌های امروز» (رفع اشکال بند ۱۶)
    final cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۷'));
    final dId = await DeviceRepo.insert(Device(customerId: cId, model: 'لپ‌تاپ'));
    final now = DateTime.now();
    final t = Ticket(
      code: 'T-P7V3-D',
      customerId: cId,
      deviceId: dId,
      intakeDate: now,
      dueDate: DateTime(now.year, now.month, now.day, 9, 0),
      dueTime: '09:00',
      estimateAmount: 300000,
      createdBy: adminId,
    );
    await TicketRepo.insert(t);
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('بند ۱۶ — نرمال‌سازی ورودی', () {
    test('حروف عربی به فارسی و نیم‌فاصله به فاصله', () {
      final n = AssistantService.normalizeQuery('يادآوري‌هاي امروز');
      expect(n, contains('یادآوری'));
      expect(n.contains('\u200C'), isFalse);
    });

    test('ارقام فارسی به انگلیسی و شماره رسید دست‌نخورده می‌ماند', () {
      final n = AssistantService.normalizeQuery('بدهی RCP-۱۴۰۵۰۹۰۴-۰۰۱');
      expect(n, contains('rcp-14050904-001'));
    });

    test('حذف علائم نگارشی و کلمات پرکننده', () {
      final n = AssistantService.normalizeQuery('لطفاً میخوام وضعیت سفارش را بدانم!');
      expect(n.contains('لطفا'), isFalse);
      expect(n.contains('میخوام'), isFalse);
      expect(n, contains('وضعیت'));
      expect(n, contains('سفارش'));
    });
  });

  group('بند ۱۶ — استخراج بازه تاریخی', () {
    test('«امروز» → بازه یک‌روزه امروز', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, to) = AssistantService.extractDateRange('فروش امروز چقدر بود؟');
      expect(from, today);
      expect(to, today);
    });

    test('«دیروز» → بازه دیروز', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, to) = AssistantService.extractDateRange('گزارش دیروز');
      expect(from, today.subtract(const Duration(days: 1)));
      expect(to, today.subtract(const Duration(days: 1)));
    });

    test('«ماه گذشته» → از اول ماه قبل تا آخرین روز ماه قبل', () {
      final now = DateTime.now();
      final firstThis = DateTime(now.year, now.month, 1);
      final firstLast = DateTime(firstThis.year, firstThis.month - 1, 1);
      final (from, to) = AssistantService.extractDateRange('فروش ماه گذشته');
      expect(from, firstLast);
      expect(to, firstThis.subtract(const Duration(days: 1)));
    });

    test('«۷ روز اخیر» → بازه هفت‌روزه تا امروز', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, to) = AssistantService.extractDateRange('فروش ۷ روز اخیر');
      expect(from, today.subtract(const Duration(days: 6)));
      expect(to, today);
    });

    test('تاریخ شمسی صریح «از ... تا ...» → تبدیل به میلادی', () {
      final (from, to) =
          AssistantService.extractDateRange('از ۱۴۰۵/۰۸/۰۱ تا ۱۴۰۵/۰۹/۰۱ فروش را بگو');
      expect(from, parseShamsi('1405/08/01'));
      expect(to, parseShamsi('1405/09/01'));
    });

    test('بدون اشاره زمانی → (null, null)', () {
      final (from, to) = AssistantService.extractDateRange('سود خالص چقدر شد؟');
      expect(from, isNull);
      expect(to, isNull);
    });
  });

  group('بند ۱۶ — تشخیص نیت بدون دیتابیس', () {
    test('«یادآوری‌های امروز» → reminders', () {
      expect(AssistantService.detectIntent('یادآوری‌های امروز'), 'reminders');
    });
    test('«وضعیت سفارش» با شماره رسید → order_status', () {
      expect(AssistantService.detectIntent('وضعیت سفارش RCP-14050904-001'),
          'order_status');
    });
    test('«خلاصه سفارش‌های باز» → orders_summary', () {
      expect(AssistantService.detectIntent('خلاصه سفارش‌های باز'), 'orders_summary');
    });
    test('«فروش این ماه» → finance', () {
      expect(AssistantService.detectIntent('فروش این ماه'), 'finance');
    });
    test('«عملکرد کاربران» → user_performance', () {
      expect(AssistantService.detectIntent('عملکرد کاربران'), 'user_performance');
    });
    test('«گارانتی‌های در هشدار» → warranty', () {
      expect(AssistantService.detectIntent('گارانتی‌های در هشدار'), 'warranty');
    });
    test('«فاکتورهای ابطال‌شده» → cancelled_invoices', () {
      expect(AssistantService.detectIntent('فاکتورهای ابطال‌شده'),
          'cancelled_invoices');
    });
    test('«بک‌آپ بگیر» → backup', () {
      expect(AssistantService.detectIntent('بک‌آپ بگیر'), 'backup');
    });
    test('«پرینت فیش شماره ...» → print_receipt', () {
      expect(AssistantService.detectIntent('پرینت فیش شماره RCP-14050904-001'),
          'print_receipt');
    });
    test('متن بی‌ربط → help', () {
      expect(AssistantService.detectIntent('سلام خوبی'), 'help');
    });
  });

  group('بند ۱۶ — یادآوری‌های امروز با داده واقعی (رفع اشکال «می‌گوید هیچ»)', () {
    test('سفارش موعد امروز با ساعت ۹ در پاسخ نیت یادآوری می‌آید', () async {
      final reply = await AssistantService.handle('یادآوری‌های امروز');
      expect(reply.text, contains('T-P7V3-D'));
      expect(reply.text, contains('09:00'));
    });
  });

  group('بند ۱۶ — شفاف‌سازی ابهام و پالایش دسترسی', () {
    test('ابهام بین دو نیت → سوال گزینه‌دار و انتخاب با شماره', () async {
      // «گزارش» و «مالی» هر دو امتیاز می‌گیرند → سوال شفاف‌سازی
      final r1 = await AssistantService.handle('گزارش مالی امروز');
      expect(r1.text, contains('کدام'));
      // پاسخ با شماره — گزینه اول اجرا می‌شود، نه پیام راهنما
      final r2 = await AssistantService.handle('1');
      expect(r2.text, contains('سود خالص'));
    });

    test('کاربر بدون دسترسی صفحه فاکتور — پاسخ انصراف مودبانه', () async {
      AppSession.I.currentUser = const AuthUser(
        id: -1,
        username: 'limited',
        displayName: 'کاربر محدود',
        role: 'user',
        isActive: true,
      );
      final reply = await AssistantService.handle('فروش این ماه');
      expect(reply.text, contains('دسترسی لازم را نداری'));
      // کاربر بدون دسترسی KPI — گزارش عملکرد هم بسته است
      final perf = await AssistantService.handle('عملکرد کاربران');
      expect(perf.text, contains('دسترسی لازم را نداری'));
      // بازگشت به ادمین برای تست‌های بعدی
      await AppSession.I.loginWith('admin', 'admin');
    });
  });

  group('بند ۱۴.۸۶ — فلش‌های RTL تقویم شمسی', () {
    testWidgets('حتی در زمینه چپ‌به‌راست، «ماه قبل» سمت راست است', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          // زمینه عمداً LTR — Directionality صریح داخل ویجت باید غلبه کند
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: Center(
              child: ShamsiCalendar(
                initial: j.Jalali(1405, 9, 1),
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final prevCenter = tester.getCenter(find.byIcon(Icons.chevron_right));
      final nextCenter = tester.getCenter(find.byIcon(Icons.chevron_left));
      expect(prevCenter.dx > nextCenter.dx, isTrue);
    });
  });
}
