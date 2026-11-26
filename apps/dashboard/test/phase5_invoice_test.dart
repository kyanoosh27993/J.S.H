/// تست‌های فاز ۵ — سفارشات، فاکتور، صندوق، QR (بندهای ۱۲، ۱۳، ۱۴ + بند ۶)
/// شماره‌گذاری استاندارد، ابطال به‌جای حذف، حذف کامل فقط مدیر، تسویه/تخفیف
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/auth_service.dart';

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
  late int tid1;
  late int tid2;
  late int adminId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase5_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    final admin = await UserRepo.byUsernameRow('admin');
    adminId = admin!['id'] as int;
    await AppSession.I.loginWith('admin', 'admin');

    final cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۵'));
    final dId = await DeviceRepo.insert(
        Device(customerId: cId, model: 'MacBook Pro'));

    final t1 = Ticket(
      code: 'T-P5-1',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 2)),
      estimateAmount: 2000000,
      createdBy: adminId,
    );
    t1.id = await TicketRepo.insert(t1);
    tid1 = t1.id!;
    await TicketItemRepo.insert(TicketItem(
      ticketId: tid1,
      description: 'تعویض کیبورد',
      qty: 1,
      price: 1500000,
    ));

    final t2 = Ticket(
      code: 'T-P5-2',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 3)),
      estimateAmount: 800000,
      createdBy: adminId,
    );
    t2.id = await TicketRepo.insert(t2);
    tid2 = t2.id!;
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('شماره‌گذاری استاندارد (بند ۱۲)', () {
    test('سال+روز ثبت + عدد افزاینده با شروع دلخواه', () async {
      await SettingsRepo.set('pre_invoice_start', '100');
      final n1 = await InvoiceRepo.nextNumber(InvoiceRepo.kindPre);
      // الگو: YYYYMMDD-####
      final parts = n1.split('-');
      expect(parts.length, 2);
      expect(parts[0].length, 8);
      expect(int.parse(parts[1]), greaterThanOrEqualTo(100));
      // پیش‌فاکتور بساز — شماره باید با همان شروع باشد
      final t = (await TicketRepo.byId(tid1))!;
      await InvoiceRepo.createFromTicket(ticket: t, kind: InvoiceRepo.kindPre);
      final map = await InvoiceRepo.allByTicketMap();
      final number = (map[tid1]!['number'] ?? '') as String;
      expect(number, n1);
      // فاکتور بعدی با شماره بعدی
      final t2 = (await TicketRepo.byId(tid2))!;
      await InvoiceRepo.createFromTicket(ticket: t2, kind: InvoiceRepo.kindPre);
      final map2 = await InvoiceRepo.allByTicketMap();
      final number2 = (map2[tid2]!['number'] ?? '') as String;
      final seq1 = int.parse(n1.split('-').last);
      final seq2 = int.parse(number2.split('-').last);
      expect(seq2, seq1 + 1);
    });

    test('پیش‌فاکتور و فاکتور شمارنده جدا دارند', () async {
      final nf = await InvoiceRepo.nextNumber(InvoiceRepo.kindFinal);
      final np = await InvoiceRepo.nextNumber(InvoiceRepo.kindPre);
      expect(nf.split('-').last, '0001'); // فاکتور هنوز ساخته نشده — شروع=۱
      expect(np.split('-').last, isNot('0001'));
    });
  });

  group('ابطال به‌جای حذف (بند ۱۳)', () {
    test('ابطال با دلیل — سند به ابطالی می‌رود', () async {
      final map = await InvoiceRepo.allByTicketMap();
      final inv = map[tid1]!;
      final id = inv['id'] as int;
      await InvoiceRepo.cancel(id, 'اشتباه در اقلام', userId: adminId);
      final db = await Db.instance();
      final row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [id])).first;
      expect(row['status'], 'cancelled');
      expect(row['cancel_reason'], 'اشتباه در اقلام');
      expect((row['cancelled_at'] ?? '') as String, isNotEmpty);
    });

    test('بازگردانی از ابطال', () async {
      final map = await InvoiceRepo.allByTicketMap();
      final id = map[tid1]!['id'] as int;
      await InvoiceRepo.restore(id);
      final db = await Db.instance();
      final row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [id])).first;
      expect(row['status'], 'active');
    });

    test('حذف کامل فقط توسط مدیر اصلی', () async {
      // کاربر محدود بدون دسترسی
      final (_, err) = await UserRepo.create(
        username: 'clerk',
        displayName: 'منشی',
        role: kRoleUser,
        password: 'clerkpass',
      );
      expect(err, isEmpty);
      await UserRepo.setPerms(
          (await UserRepo.byUsernameRow('clerk'))!['id'] as int, ['page.home']);
      final clerk = await UserRepo.byId(
          (await UserRepo.byUsernameRow('clerk'))!['id'] as int);
      final map = await InvoiceRepo.allByTicketMap();
      final id = map[tid2]!['id'] as int;
      final errMsg = await InvoiceRepo.deleteFully(id, actor: clerk);
      expect(errMsg, isNotNull); // ممنوع
      // مدیر اصلی مجاز
      final adminUser = await UserRepo.byId(adminId);
      final err2 = await InvoiceRepo.deleteFully(id, actor: adminUser);
      expect(err2, isNull);
      final db = await Db.instance();
      final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
      expect(rows, isEmpty); // حذف کامل
    });
  });

  group('صندوق — تسویه و تخفیف (بند ۱۴)', () {
    test('تسویه مانده با کاربر وصول‌کننده', () async {
      final t = (await TicketRepo.byId(tid1))!;
      final invId =
          await InvoiceRepo.createFromTicket(ticket: t, kind: InvoiceRepo.kindFinal);
      await InvoiceRepo.settle(invId, tid1, userId: adminId);
      final db = await Db.instance();
      final row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [invId])).first;
      expect(row['remaining'], 0);
      final paid = await PaymentRepo.paidSum(tid1);
      expect(paid, 1500000);
      final payments = await db.query('payments', where: 'ticket_id = ?', whereArgs: [tid1]);
      expect(payments.last['user_id'], adminId);
    });

    test('تخفیف نقدی و درصدی مانده را کم می‌کند', () async {
      final t = (await TicketRepo.byId(tid2))!;
      final invId =
          await InvoiceRepo.createFromTicket(ticket: t, kind: InvoiceRepo.kindPre);
      await InvoiceRepo.applyDiscount(invId, amount: 100000);
      final db = await Db.instance();
      var row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [invId])).first;
      expect(row['discount'], 100000);
      expect(row['remaining'], 800000 - 100000);
      await InvoiceRepo.applyDiscount(invId, percent: 10);
      row = (await db.query('invoices', where: 'id = ?', whereArgs: [invId])).first;
      // ۱۰٪ از جمع ۸۰۰٬۰۰۰ = ۸۰٬۰۰۰
      expect(row['discount'], 80000);
      expect(row['remaining'], 720000);
    });

    test('افزودن قلم از صندوق — جمع فاکتور به‌روز می‌شود', () async {
      final t = (await TicketRepo.byId(tid2))!;
      await TicketItemRepo.insert(TicketItem(
        ticketId: tid2,
        description: 'پد حرارتی',
        qty: 1,
        price: 200000,
      ));
      await InvoiceRepo.refreshForTicket(tid2);
      final map = await InvoiceRepo.allByTicketMap();
      final inv = map[tid2]!;
      // اقلام > ۰ → جمع فاکتور = جمع اقلام (نه برآورد)
      expect(inv['total'], 200000);
      expect(inv['remaining'], 120000); // 200000 - 80000 تخفیف
    });
  });

  group('باز کردن سند با شماره (بند ۶ جدید)', () {
    test('جستجو با شماره فاکتور یا کد سفارش', () async {
      final map = await InvoiceRepo.allByTicketMap();
      final number = (map[tid1]?['number'] ?? '') as String;
      // با شماره فاکتور
      final byNumber = await InvoiceRepo.findByNumberOrCode(number);
      expect(byNumber, isNotNull);
      expect(byNumber!['ticket_id'], tid1);
      // با کد سفارش
      final byCode = await InvoiceRepo.findByNumberOrCode('T-P5-2');
      expect(byCode, isNotNull);
      expect(byCode!['ticket_id'], tid2);
      // ناموجود
      final none = await InvoiceRepo.findByNumberOrCode('NOPE-999');
      expect(none, isNull);
    });
  });
}
