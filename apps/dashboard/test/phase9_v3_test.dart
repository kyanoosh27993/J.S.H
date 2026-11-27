/// تست‌های فاز ۹ نقشه راه نسخه ۳
/// بند ۲۵: تنظیم قلم‌به‌قلم گارانتی — آخرین تنظیم حاکم + ردیف حسابرسی
/// بند ۲۶: کوئری ابطالی‌های فاکتور در بازه زمانی
/// بند ۲۷: حذف یادآوری + سازنده xlsx معتبر (بدون بسته اکسل — با package:archive)
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/daily_report_service.dart';

/// تبدیل امن محتوای فایل آرشیو به متن — بسته archive در نسخه‌های مختلف
/// محتوا را String یا bytes برمی‌گرداند
String _archiveText(dynamic content) =>
    content is String ? content : utf8.decode(content as List<int>);

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
  late int itemId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase9_v3_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();

    cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۹'));
    dId = await DeviceRepo.insert(Device(customerId: cId, model: 'گوشی فاز ۹'));

    final t = Ticket(
      code: 'T-P9-1',
      customerId: cId,
      deviceId: dId,
      intakeDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 3)),
      estimateAmount: 400000,
    );
    t.id = await TicketRepo.insert(t);
    tid = t.id!;

    // قلم گارانتی‌دار — بند ۲۵
    itemId = await TicketItemRepo.insert(TicketItem(
      ticketId: tid,
      kind: 'part',
      description: 'قطعه با گارانتی',
      price: 250000,
      warrantyMonths: 6,
    ));
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('بند ۲۵ — تنظیم گارانتی قلم‌به‌قلم', () {
    test('کاهش مدت → آخرین تنظیم حاکم + ردیف حسابرسی warranty_adjust',
        () async {
      final oldEnd = DateTime.now().add(const Duration(days: 100));
      await WarrantyAdjustRepo.add(
        ticketId: tid,
        itemId: itemId,
        oldEnd: oldEnd,
        newEnd: DateTime.now().add(const Duration(days: 30)),
        action: 'reduce',
        reason: 'تست کاهش',
        userId: 1,
      );
      final latest = await WarrantyAdjustRepo.latestFor(
          ticketId: tid, itemId: itemId);
      expect(latest, isNotNull);
      expect(latest!.action, 'reduce');
      expect(latest.itemId, itemId);
      expect(latest.newEnd.isBefore(oldEnd), isTrue);
      expect(latest.reason, 'تست کاهش');

      // تنظیم دوم باید حاکم شود (آخرین ردیف برنده است)
      final extEnd = DateTime.now().add(const Duration(days: 200));
      await WarrantyAdjustRepo.add(
        ticketId: tid,
        itemId: itemId,
        oldEnd: latest.newEnd,
        newEnd: extEnd,
        action: 'extend',
        reason: 'تست افزایش',
        userId: 1,
      );
      final latest2 = await WarrantyAdjustRepo.latestFor(
          ticketId: tid, itemId: itemId);
      expect(latest2!.action, 'extend');
      expect(latest2.newEnd.isAfter(oldEnd), isTrue);

      // حسابرسی — ردیف warranty_adjust ثبت شده باشد
      final db = await Db.instance();
      final audits = await db.query('audit_log',
          where: 'action = ?', whereArgs: ['warranty_adjust']);
      expect(audits, isNotEmpty);
      final details = audits
          .map((a) => (a['detail'] ?? '') as String)
          .where((d) => d.contains('سفارش #$tid'))
          .toList();
      expect(details, isNotEmpty);
    });
  });

  group('بند ۲۶ — کوئری ابطالی‌ها در بازه', () {
    test('ابطال فاکتور → cancelledInRange آن را برمی‌گرداند', () async {
      final t = (await TicketRepo.byId(tid))!;
      final invId = await InvoiceRepo.createFromTicket(
          ticket: t, kind: InvoiceRepo.kindFinal);
      await InvoiceRepo.cancel(invId, 'دلیل تست ابطال', userId: 1);

      final now = DateTime.now();
      final rows = await InvoiceRepo.cancelledInRange(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      expect(rows, isNotEmpty);
      final hit = rows.firstWhere((r) => r['id'] == invId);
      expect((hit['status'] ?? '') as String, 'cancelled');
      expect((hit['cancel_reason'] ?? '') as String, 'دلیل تست ابطال');
      expect((hit['cancelled_at'] ?? '') as String, isNotEmpty);
    });
  });

  group('بند ۲۷ — حذف یادآوری و سازنده xlsx', () {
    test('ReminderRepo.delete ردیف را حذف می‌کند', () async {
      final rid = await ReminderRepo.insert(Reminder(
        ticketId: tid,
        remindAt: DateTime.now(),
        message: 'یادآوری تست فاز ۹',
      ));
      var pending =
          await ReminderRepo.pendingBefore(DateTime.now().add(const Duration(days: 1)));
      expect(pending.any((r) => r.id == rid), isTrue);
      await ReminderRepo.delete(rid);
      pending =
          await ReminderRepo.pendingBefore(DateTime.now().add(const Duration(days: 1)));
      expect(pending.any((r) => r.id == rid), isFalse);
    });

    test('سازنده xlsx فایل معتبر zip با workbook و sheet1 می‌سازد', () {
      final day = DateTime(2026, 5, 4, 10, 30);
      final bytes = DailyReportService.buildXlsx(day, [
        const DailyReportEntry('۱۰:۳۰', 'پذیرش', 'ثبت سفارش T-P9-1'),
        const DailyReportEntry('۱۱:۴۵', 'ابطال', 'ابطال سند ۲۰۲۶۰۵۰۴-۰۰۰۱'),
      ]);
      expect(bytes, isNotEmpty);

      // باز کردن به‌عنوان zip معتبر — اجزای حداقلی xlsx
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names.contains('xl/workbook.xml'), isTrue);
      expect(names.contains('xl/worksheets/sheet1.xml'), isTrue);

      // در بسته archive نسخه ۴ جستجوی فایل با find است
      final sheet = _archiveText(archive.find('xl/worksheets/sheet1.xml')!.content);
      // مقدار سلول در sheet1 باشد (inlineStr) — متن و تاریخ شمسی فارسی
      expect(sheet.contains('ثبت سفارش T-P9-1'), isTrue);
      expect(sheet.contains('پذیرش'), isTrue);
      expect(sheet.contains('<worksheet'), isTrue);

      final workbook = _archiveText(archive.find('xl/workbook.xml')!.content);
      expect(workbook.contains('<workbook'), isTrue);
      expect(workbook.contains('sheet'), isTrue);
    });
  });
}
