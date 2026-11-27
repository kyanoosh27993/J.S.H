/// تست‌های فاز ۱ نقشه راه نسخه ۳ — رفع باگ‌های بحرانی
/// بند ۲۰: سفارش با موعد نامشخص نباید صفحات را کرش دهد
/// بند ۱۷: صدور هم‌زمان پیش‌فاکتور و فاکتور یک روز نباید تداخل شماره بدهد
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/reminder_service.dart';

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
  late int tidUnknownDue;
  late int tidPre;
  late int tidFinal;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase1_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    final admin = await UserRepo.byUsernameRow('admin');
    adminId = admin!['id'] as int;
    await AppSession.I.loginWith('admin', 'admin');

    final cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۱'));
    final dId = await DeviceRepo.insert(Device(customerId: cId, model: 'آیفون'));

    // سفارش با موعد نامشخص (due_unknown) و ساعت '--:--' — بند ۲۰
    final tU = Ticket(
      code: 'T-P1V3-U',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now(),
      dueTime: '--:--',
      dueUnknown: true,
      estimateAmount: 500000,
      createdBy: adminId,
    );
    tU.id = await TicketRepo.insert(tU);
    tidUnknownDue = tU.id!;

    final tP = Ticket(
      code: 'T-P1V3-P',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 1)),
      estimateAmount: 900000,
      createdBy: adminId,
    );
    tP.id = await TicketRepo.insert(tP);
    tidPre = tP.id!;

    final tF = Ticket(
      code: 'T-P1V3-F',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 2)),
      estimateAmount: 700000,
      createdBy: adminId,
    );
    tF.id = await TicketRepo.insert(tF);
    tidFinal = tF.id!;
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('بند ۲۰ — موعد نامشخص نباید کرش بدهد', () {
    test('buildTask روی سفارش با ساعت --:-- بدون خطا کار می‌کند', () async {
      final t = (await TicketRepo.byId(tidUnknownDue))!;
      final task = await ReminderService.buildTask(t);
      expect(task.ticket.id, tidUnknownDue);
      expect(task.collectable, isNonNegative);
    });

    test('dueBetween ردیف موعد نامشخص را هم برمی‌گرداند و buildTask همه سبز است',
        () async {
      final now = DateTime.now();
      final due = await TicketRepo.dueBetween(
          now.subtract(const Duration(days: 1)), now.add(const Duration(days: 7)));
      expect(due.any((t) => t.id == tidUnknownDue), isTrue);
      for (final t in due) {
        await ReminderService.buildTask(t); // نباید پرتاب کند
      }
    });
  });

  group('بند ۱۷ — شماره فاکتور پیش/قطعی یک روز تداخل نکند', () {
    test('پیش‌فاکتور و فاکتور قطعی با شروع پیش‌فرض ۱ هم‌زمان ساخته می‌شوند',
        () async {
      await SettingsRepo.set('pre_invoice_start', '1');
      await SettingsRepo.set('invoice_start', '1');
      final t1 = (await TicketRepo.byId(tidPre))!;
      await InvoiceRepo.createFromTicket(
          ticket: t1, kind: InvoiceRepo.kindPre);
      final t2 = (await TicketRepo.byId(tidFinal))!;
      // تا پیش از اصلاح اینجا UNIQUE(number) سراسری کرش می‌داد
      await InvoiceRepo.createFromTicket(
          ticket: t2, kind: InvoiceRepo.kindFinal);
      final map = await InvoiceRepo.allByTicketMap();
      final preNum = (map[tidPre]!['number'] ?? '') as String;
      final finNum = (map[tidFinal]!['number'] ?? '') as String;
      expect(preNum, isNotEmpty);
      expect(finNum, isNotEmpty);
      expect((map[tidPre]!['kind'] ?? '') as String, InvoiceRepo.kindPre);
      expect((map[tidFinal]!['kind'] ?? '') as String, InvoiceRepo.kindFinal);
    });
  });
}
