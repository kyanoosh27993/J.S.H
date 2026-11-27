/// تست‌های فاز ۵b — بند ۱۲ (هزینه/تخفیف/خسارت و سود خالص)، بند ۱۰.۶۹
/// (نوع قلم)، بند ۲۳ (ابطال و خروج از صندوق) و لاگ اصلاح مبالغ برای مدیر سیستم.
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
  late int cId;
  late int dId;
  late int tid;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase5_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    await AppSession.I.loginWith('admin', 'admin');

    cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۵b'));
    dId = await DeviceRepo.insert(Device(customerId: cId, model: 'سامسونگ'));

    final t = Ticket(
      code: 'T-P5V3-A',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 1)),
      estimateAmount: 1000000,
    );
    t.id = await TicketRepo.insert(t);
    tid = t.id!;
    await TicketItemRepo.insert(TicketItem(
      ticketId: tid,
      kind: 'part',
      description: 'صفحه‌نمایش',
      qty: 1,
      price: 1200000,
    ));
    await TicketItemRepo.insert(TicketItem(
      ticketId: tid,
      kind: 'service',
      type: 'discount',
      description: 'تخفیف وفاداری',
      qty: 1,
      price: -200000,
    ));
  });

  test('بند ۱۲ — createFromTicket هزینه/تخفیف/خسارت را ذخیره و سود خالص را درست محاسبه می‌کند',
      () async {
    final t = (await TicketRepo.byId(tid))!;
    final id = await InvoiceRepo.createFromTicket(
      ticket: t,
      kind: InvoiceRepo.kindFinal,
      discount: 50000,
      cost: 300000,
      damage: 100000,
      damageUserId: 1,
      profitNote: 'یادداشت تست',
    );
    final db = await Db.instance();
    final rows =
        await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    expect(rows, isNotEmpty);
    final r = rows.first;
    // جمع = قطعه + خدمات − تخفیف قلمی = 1,200,000 + 0 − 200,000
    expect((r['total'] ?? 0) as int, 1000000);
    expect((r['discount'] ?? 0) as int, 50000);
    expect((r['cost'] ?? 0) as int, 300000);
    expect((r['damage'] ?? 0) as int, 100000);
    expect((r['damage_user'] ?? 0) as int, 1);
    expect((r['profit_note'] ?? '') as String, 'یادداشت تست');
    // سود خالص = جمع − تخفیف − هزینه − خسارت = 1,000,000 − 50,000 − 300,000 − 100,000
    expect(InvoiceRepo.netProfitOf(r), 550000);
  });

  test('بند ۱۲ — updateFinancials تغییر مبالغ را در لاگ مدیر ثبت می‌کند',
      () async {
    final db = await Db.instance();
    final rows = await db.query('invoices',
        where: 'kind = ?', whereArgs: [InvoiceRepo.kindFinal], limit: 1);
    expect(rows, isNotEmpty);
    final id = rows.first['id'] as int;
    await InvoiceRepo.updateFinancials(
      id,
      cost: 250000,
      discount: 60000,
      damage: 90000,
      damageUserId: 2,
      profitNote: 'اصلاح شد',
      userId: 99,
    );
    final after = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    expect((after.first['cost'] ?? 0) as int, 250000);
    expect((after.first['discount'] ?? 0) as int, 60000);
    final logs = await db.query('audit_log',
        where: 'action = ?', whereArgs: ['invoice_cost_edit']);
    expect(logs, isNotEmpty);
    final detail = (logs.first['detail'] ?? '') as String;
    // لاگ باید مقدار قدیمی و جدید را هم داشته باشد (بند ۱۲)
    expect(detail, contains('قبلی'));
    expect(detail, contains('جدید'));
    expect(detail, contains('کاربر #99'));
  });

  test('بند ۱۰.۶۹ — قلم بدون نوع، پیش‌فرض خوانده می‌شود و نوع تخفیف/خسارت حفظ می‌شود',
      () async {
    // قلم قدیمی بدون type — خواندن باید type='' بدهد (سازگاری با نصب‌های قبل)
    final items = await TicketItemRepo.byTicket(tid);
    expect(items, isNotEmpty);
    expect(items.first.type, '');
    // قلم تخفیفی با قیمت منفی و قلم خسارت (خارج از جمع)
    await TicketItemRepo.insert(TicketItem(
      ticketId: tid,
      type: 'damage',
      description: 'ضربه فنی توسط کاربر',
      qty: 1,
      price: 150000,
    ));
    final after = await TicketItemRepo.byTicket(tid);
    final dmg = after.last;
    expect(dmg.type, 'damage');
    expect(dmg.countsInTotal, isFalse);
    final disc = after.where((i) => i.type == 'discount').first;
    expect(disc.countsInTotal, isTrue);
    expect(disc.price, -200000);
  });

  test('بند ۲۳ — فاکتور ابطالی از نقشه صندوق (غیر ابطالی) حذف می‌شود',
      () async {
    // سفارش مستقل تا فاکتور قطعی سفارش اصلی نتیجه را مخدوش نکند
    final t2 = Ticket(
      code: 'T-P5V3-B',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 2)),
      estimateAmount: 400000,
    );
    t2.id = await TicketRepo.insert(t2);
    final preId = await InvoiceRepo.createFromTicket(
        ticket: t2, kind: InvoiceRepo.kindPre);
    final before = await InvoiceRepo.activeByTicketMap();
    expect(before[t2.id], isNotNull);
    await InvoiceRepo.cancel(preId, 'تست ابطال', userId: 1);
    final after = await InvoiceRepo.activeByTicketMap();
    expect(after[t2.id], isNull);
  });
}
