/// تست‌های فاز ۴ نقشه راه نسخه ۳ — آمار خانه
/// ۱) فیلتر بازه تاریخی HomeStatsService برای فاکتورها و سفارش‌ها
/// ۲) کمک‌تابع جمع مرکز دونات
/// ۳) آمار گارانتی با دو منبع ترکیبی (رکورد + اقلام warranty_months)
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/forecast_service.dart';
import 'package:jsh_service_dashboard/core/services/home_stats_service.dart';
import 'package:jsh_service_dashboard/shared/charts/modern_charts.dart';

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
  late int cId;
  late int dId;
  late int tidInRange; // سفارش داخل بازه (پذیرش امروز)
  late int tidOutRange; // سفارش بیرون بازه (پذیرش ۶۰ روز پیش)
  late int tidWarranty; // سفارش تحویل‌شده با قلم گارانتی‌دار
  late int tidCancelled; // سفارش فاکتور ابطالی (برای آزمون حذف از جمع)

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase4_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    final admin = await UserRepo.byUsernameRow('admin');
    adminId = admin!['id'] as int;
    await AppSession.I.loginWith('admin', 'admin');

    cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۴'));
    dId = await DeviceRepo.insert(Device(customerId: cId, model: 'گوشی فاز ۴'));

    final now = DateTime.now();

    // سفارش داخل بازه — پذیرش امروز
    final tA = Ticket(
      code: 'T-P4-IN',
      customerId: cId,
      deviceId: dId,
      intakeDate: now,
      dueDate: now.add(const Duration(days: 3)),
      estimateAmount: 400000,
      createdBy: adminId,
    );
    tA.id = await TicketRepo.insert(tA);
    tidInRange = tA.id!;

    // سفارش بیرون بازه — پذیرش ۶۰ روز پیش
    final tB = Ticket(
      code: 'T-P4-OUT',
      customerId: cId,
      deviceId: dId,
      intakeDate: now.subtract(const Duration(days: 60)),
      dueDate: now.add(const Duration(days: 3)),
      estimateAmount: 800000,
      createdBy: adminId,
    );
    tB.id = await TicketRepo.insert(tB);
    tidOutRange = tB.id!;

    // سفارش گارانتی — تحویل‌شده با قلم ۱۲ ماهه (بدون created_by تا از KPI کاربران کنار برود)
    final tW = Ticket(
      code: 'T-P4-WAR',
      customerId: cId,
      deviceId: dId,
      intakeDate: now,
      dueDate: now,
    );
    tW.id = await TicketRepo.insert(tW);
    tidWarranty = tW.id!;
    await TicketItemRepo.insert(TicketItem(
      ticketId: tidWarranty,
      kind: 'part',
      description: 'قطعه گارانتی‌دار فاز ۴',
      qty: 1,
      price: 100000,
      warrantyMonths: 12,
    ));

    // سفارش فاکتور ابطالی — پذیرش امروز (createdBy ندارد)
    final tC = Ticket(
      code: 'T-P4-CANC',
      customerId: cId,
      deviceId: dId,
      intakeDate: now,
      dueDate: now,
      estimateAmount: 250000,
    );
    tC.id = await TicketRepo.insert(tC);
    tidCancelled = tC.id!;
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('کمک‌تابع جمع مرکز دونات (فاز ۴)', () {
    test('جمع مقادیر نقاط — رفع باگ نمایش تعداد قطاع‌ها به‌جای جمع', () {
      expect(
        donutTotal([
          const ChartPoint('پذیرش', 2),
          const ChartPoint('تحویل', 3),
          const ChartPoint('تعمیر', 7),
        ]),
        12,
      );
      expect(donutTotal(const []), 0);
      expect(donutTotal([const ChartPoint('فقط یکی', 5.5)]), 5.5);
    });
  });

  group('خلاصه مالی — فیلتر بازه و فاکتور ابطالی', () {
    test('فقط فاکتورهای قطعی فعال داخل بازه شمرده می‌شوند', () async {
      final db = await Db.instance();
      final now = DateTime.now();

      // فاکتور قطعی برای سفارش داخل بازه — صادره امروز
      final tIn = (await TicketRepo.byId(tidInRange))!;
      await TicketItemRepo.insert(TicketItem(
        ticketId: tidInRange,
        description: 'خدمت تعمیر',
        qty: 1,
        price: 400000,
      ));
      final invIn = await InvoiceRepo.createFromTicket(
          ticket: tIn, kind: InvoiceRepo.kindFinal, discount: 50000);
      // issued_at دقیقاً امروز
      await db.update('invoices',
          {'issued_at': now.toIso8601String()}, where: 'id = ?', whereArgs: [invIn]);

      // فاکتور قطعی بیرون بازه — صادره ۹۰ روز پیش
      final tOut = (await TicketRepo.byId(tidOutRange))!;
      final invOut = await InvoiceRepo.createFromTicket(
          ticket: tOut, kind: InvoiceRepo.kindFinal);
      await db.update(
          'invoices',
          {
            'issued_at':
                now.subtract(const Duration(days: 90)).toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [invOut]);

      // فاکتور ابطالی داخل بازه — نباید در جمع بیاید (فاکتور سفارش جداگانه)
      final tCan = (await TicketRepo.byId(tidCancelled))!;
      final invCancelled = await InvoiceRepo.createFromTicket(
          ticket: tCan, kind: InvoiceRepo.kindFinal);
      await InvoiceRepo.cancel(invCancelled, 'تست ابطال');
      await db.update('invoices',
          {'issued_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [invCancelled]);

      // بازه: ۳۰ روز پیش تا امروز — فقط فاکتور سفارش داخل بازه
      final from = now.subtract(const Duration(days: 30));
      final fin = await HomeStatsService.financialSummary(from, now);
      expect(fin.gross, 400000);
      expect(fin.discounts, 50000);
      expect(fin.net, 350000);
      expect(fin.count, 1);

      // همه زمان‌ها: هر دو فاکتور فعال (ابطالی حذف)
      final all = await HomeStatsService.financialSummary(null, null);
      expect(all.gross, 1200000);
      expect(all.count, 2);
    });
  });

  group('شاخص عملکرد کاربران — فیلتر بازه', () {
    test('فقط سفارش‌های پذیرش داخل بازه برای کاربر شمرده می‌شوند', () async {
      final now = DateTime.now();
      // تحویل سفارش داخل بازه
      await TicketRepo.changeStatus(tidInRange, 'delivered', userId: adminId);
      // سفارش بیرون بازه هم تحویل شود — نباید داخل بازه دیده شود
      await TicketRepo.changeStatus(tidOutRange, 'delivered', userId: adminId);

      // بازه دیروز تا فردا — فقط سفارش امروز
      final kpis = await HomeStatsService.employeeKpis(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      final me = kpis.where((k) => k.userId == adminId).toList();
      expect(me, isNotEmpty);
      expect(me.first.created, 1);
      expect(me.first.delivered, 1);
      expect(me.first.share, closeTo(100, 0.01));

      // همه زمان‌ها — هر دو سفارش
      final all = await HomeStatsService.employeeKpis(null, null);
      final meAll = all.where((k) => k.userId == adminId).toList();
      expect(meAll, isNotEmpty);
      expect(meAll.first.created, 2);
      expect(meAll.first.delivered, 2);
    });
  });

  group('آمار گارانتی — ترکیب دو منبع (رفع همیشه-صفر)', () {
    test('رکورد تحویل قدیمی منقضی + قلم warranty_months منقضی هر دو شمرده می‌شوند',
        () async {
      final db = await Db.instance();
      final now = DateTime.now();

      // منبع ۱ — رکورد warranty_records با پایان ۱ ماه پیش (منقضی)
      await db.insert('warranty_records', {
        'ticket_id': tidWarranty,
        'start_date': now
            .subtract(const Duration(days: 390))
            .toIso8601String(),
        'end_date': now.subtract(const Duration(days: 30)).toIso8601String(),
        'months': 12,
        'status': 'active',
        'created_at': now.toIso8601String(),
      });

      // منبع ۲ — سفارش تحویل‌شده با updated_at ۱۳ ماه پیش و قلم ۱۲ ماهه
      // → پایان گارانتی ۱ ماه پیش = منقضی
      await TicketRepo.changeStatus(tidWarranty, 'delivered', userId: adminId);
      await db.update(
          'tickets',
          {
            'updated_at': DateTime(
                    now.year, now.month - 13, now.day)
                .toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [tidWarranty]);

      final alerts = await ForecastService.warrantyAlertDetails();
      final forTicket = alerts.where((a) => a.ticketId == tidWarranty).toList();

      // هر دو منبع باید برای این سفارش آورده شوند و منقضی شمرده شوند
      // (ممکن است گارانتی‌های دیگری از مسیر تحویل هم ساخته شده باشند)
      expect(forTicket.any((a) => a.fromRecord && a.expired), isTrue);
      expect(forTicket.any((a) => !a.fromRecord && a.expired), isTrue);

      // آمار ترکیبی — منقضی حداقل ۲ (رکورد + قلم)
      final stats = await ForecastService.warrantyStats();
      expect(stats.expired >= 2, isTrue);
      expect(stats.expiring, greaterThanOrEqualTo(0));
    });
  });
}
