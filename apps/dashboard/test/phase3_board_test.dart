/// تست‌های فاز ۳ — کارتابل لیستی، تحویل با تاییدیه/تسویه و تبدیل پیش‌فاکتور
/// به فاکتور، سایدبار اندروید محدود (بند ۱۱ + بند ۵)
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/delivery_service.dart';
import 'package:jsh_service_dashboard/features/board/board.dart';

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
  late int ticketId;
  late int adminId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    final admin = await UserRepo.byUsernameRow('admin');
    adminId = admin!['id'] as int;
    // ورود مدیر برای ثبت کاربر عملیات‌ها
    await AppSession.I.loginWith('admin', 'admin');

    final cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۳'));
    final dId = await DeviceRepo.insert(
        Device(customerId: cId, model: 'لپ‌تاپ ایسوس'));
    ticketId = await TicketRepo.insert(Ticket(
      code: 'T-P3-1',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 2)),
      estimateAmount: 2000000,
      createdBy: adminId,
    ));
    await TicketItemRepo.insert(TicketItem(
      ticketId: ticketId,
      description: 'تعویض باتری',
      qty: 1,
      price: 1500000,
    ));
    await PaymentRepo.insert(Payment(
      ticketId: ticketId,
      amount: 500000,
      kind: 'deposit',
      userId: adminId,
    ));
    // بردن سفارش تا «آماده تحویل»
    await TicketRepo.changeStatus(ticketId, 'diagnosis', userId: adminId);
    await TicketRepo.changeStatus(ticketId, 'repairing', userId: adminId);
    await TicketRepo.changeStatus(ticketId, 'testing', userId: adminId);
    await TicketRepo.changeStatus(ticketId, 'ready', userId: adminId);
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('تحویل با تاییدیه و تسویه (بند ۱۱)', () {
    test('باقیمانده درست محاسبه می‌شود', () async {
      final t = await TicketRepo.byId(ticketId);
      expect(await DeliveryService.totalOf(t!), 1500000); // اقلام > برآورد
      expect(await DeliveryService.remainingOf(t), 1000000);
    });

    test('تحویل با بدهی — بدون پرداخت، فاکتور با بدهی ثبت می‌شود', () async {
      final t = await TicketRepo.byId(ticketId);
      final result = await DeliveryService.deliver(
        t!,
        decision: DeliveryDecision.deliverWithDebt,
      );
      expect(result.ok, isTrue);
      expect(result.invoiceId, greaterThan(0));
      // وضعیت تحویل شد
      expect((await TicketRepo.byId(ticketId))!.status, 'delivered');
      // فاکتور ساخته شد — پیش‌فاکتور → فاکتور
      final db = await Db.instance();
      final inv = (await db.query('invoices',
          where: 'ticket_id = ?', whereArgs: [ticketId])).first;
      expect(inv['total'], 1500000);
      expect(inv['paid'], 500000);
      expect(inv['remaining'], 1000000);
      // دلیل ثبت‌شده در تاریخچه — تایید صریح بدهی
      final log = await TicketRepo.statusLog(ticketId);
      expect(log.last['to_status'], 'delivered');
      expect((log.last['reason'] as String).contains('بدهی'), isTrue);
      // گارانتی خودکار
      final w = await db.query('warranty_records',
          where: 'ticket_id = ?', whereArgs: [ticketId]);
      expect(w, isNotEmpty);
    });

    test('تسویه کامل و تحویل — پرداخت با کاربر وصول‌کننده ثبت می‌شود',
        () async {
      // سفارش دوم
      final cId = await CustomerRepo.insert(Customer(name: 'مشتری تسویه'));
      final dId = await DeviceRepo.insert(
          Device(customerId: cId, model: 'PS5'));
      final tid = await TicketRepo.insert(Ticket(
        code: 'T-P3-2',
        customerId: cId,
        deviceId: dId,
        intakeDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 1)),
        estimateAmount: 800000,
      ));
      await TicketRepo.changeStatus(tid, 'ready', userId: adminId);
      final t = await TicketRepo.byId(tid);
      final result = await DeliveryService.deliver(
        t!,
        decision: DeliveryDecision.settleAndDeliver,
      );
      expect(result.ok, isTrue);
      // پرداخت نهایی کامل ثبت شد
      final paid = await PaymentRepo.paidSum(tid);
      expect(paid, 800000);
      final db = await Db.instance();
      final payments = await db.query('payments', where: 'ticket_id = ?', whereArgs: [tid]);
      expect(payments.length, 1);
      expect(payments.first['user_id'], adminId);
      expect(payments.first['amount'], 800000);
      // فاکتور بدون بدهی
      final inv = (await db.query('invoices', where: 'ticket_id = ?', whereArgs: [tid])).first;
      expect(inv['remaining'], 0);
    });

    test('تحویل دوباره — فاکتور تکراری ساخته نمی‌شود', () async {
      final t = await TicketRepo.byId(ticketId);
      // تغییر وضعیت دستی به ready برای شبیه‌سازی
      await TicketRepo.changeStatus(ticketId, 'ready', userId: adminId);
      await DeliveryService.deliver(t!, decision: DeliveryDecision.settleAndDeliver);
      final db = await Db.instance();
      final invoices = await db.query('invoices',
          where: 'ticket_id = ?', whereArgs: [ticketId]);
      expect(invoices.length, 1); // همان رکورد قبلی به‌روزرسانی شد
      expect(invoices.first['remaining'], 0); // حالا تسویه کامل
    });
  });

  group('کارتابل لیستی رنگی (بند ۱۱)', () {
    // بارگذاری با I/O واقعی — تناوب runAsync/pump تا پایان لودینگ
    Future<void> waitLoaded(WidgetTester tester) async {
      for (var k = 0; k < 25; k++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          return;
        }
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('لیست رندر می‌شود و فیلتر وضعیت کار می‌کند', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: Scaffold(body: BoardPage()),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await waitLoaded(tester);
      await tester.pump(const Duration(milliseconds: 200));

      // ردیف سفارش تحویل‌شده با چیپ وضعیت
      expect(find.text('تحویل شده'), findsWidgets);
      // فیلتر وضعیت = پذیرش → هیچ ردیفی در این وضعیت نیست (هر دو تحویل شدند)
      await tester.tap(find.text('همه وضعیت‌ها').first);
      await tester.pump(const Duration(milliseconds: 400));
      final opt = find.text('پذیرش');
      expect(opt.evaluate().isNotEmpty, isTrue, reason: 'منوی فیلتر باز نشد');
      await tester.tap(opt.last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('سفارشی با این فیلترها نیست'), findsOneWidget);
      // باز کردن درخت و اطمینان از نبود تایمر معلق (منوی دراپ‌داون و غیره)
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('سایدبار اندروید (بند ۵)', () {
    testWidgets('در عرض موبایل نمایش داده می‌شود ولی کل صفحه را نمی‌گیرد',
        (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: Scaffold(body: BoardPage()),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      for (var k = 0; k < 20; k++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 200));
      // در این صفحه جستجو/فیلتر در اسکرول افقی جا می‌شود — لیست عمودی اسکرول دارد
      expect(find.byType(ListView), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
