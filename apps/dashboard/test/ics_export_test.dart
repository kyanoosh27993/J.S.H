/// تولید خروجی Google Calendar برای سفارشات فردا — مسیر مخازن برنامه
/// (تاریخ‌ها داینامیک‌اند تا تست مستقل از روز اجرا باشد)
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/calendar_export_service.dart';
import 'package:jsh_service_dashboard/core/services/reminder_service.dart';

class _FakePP extends PathProviderPlatform {
  final String base;
  late final String supportPath = '$base/support';
  late final String docsPath = '$base/docs';
  _FakePP(this.base);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

const orders = <Map<String, String>>[
  {
    'name': 'علی رضایی', 'phone': '09134410001', 'nid': '5321123456',
    'model': 'iPhone 13', 'serial': '356938035643801',
    'defect': 'تصویر نمی‌آید', 'state': 'روشن می‌شود', 'time': '08:00',
    'estimate': '2500000', 'deposit': '500000', 'acc': 'درب پشت',
  },
  {
    'name': 'مهدی نیکو', 'phone': '09134410002', 'nid': '5321123457',
    'model': 'PlayStation 5', 'serial': 'PS5-CFI-1215A',
    'defect': 'روشن نمی‌شود', 'state': 'کابل سالم', 'time': '09:00',
    'estimate': '1800000', 'deposit': '300000', 'acc': 'باتری',
  },
  {
    'name': 'زهرا محمدی', 'phone': '09134410003', 'nid': '5321123458',
    'model': 'لپ‌تاپ Lenovo ThinkPad', 'serial': 'LNV-TP-8821',
    'defect': 'باتری شارژ نگه نمی‌دارد', 'state': 'نمایشگر سالم', 'time': '10:00',
    'estimate': '1200000', 'deposit': '200000', 'acc': 'مموری',
  },
  {
    'name': 'حسین کریمی', 'phone': '09134410004', 'nid': '5321123459',
    'model': 'Xbox Series X', 'serial': 'XSX-2234-JSH',
    'defect': 'دیسک را نمی‌خواند', 'state': 'فن سالم', 'time': '11:00',
    'estimate': '900000', 'deposit': '0', 'acc': '',
  },
  {
    'name': 'سارا احمدی', 'phone': '09134410005', 'nid': '5321123460',
    'model': 'Samsung Galaxy S22', 'serial': '356938035643809',
    'defect': 'صفحه لمس نمی‌شود', 'state': 'نمایشگر سالم', 'time': '12:00',
    'estimate': '3100000', 'deposit': '600000', 'acc': 'سیم کارت',
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  // فردای واقعی — تست مستقل از تاریخ اجرا (رفع خطای تاریخ ثابت)
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  String icsDay(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_ics');
    PathProviderPlatform.instance = _FakePP(tempDir.path);
    await Db.instance();
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('ثبت ۵ سفارش فردا از مخازن برنامه + خروجی Google Calendar', () async {
    final codes = <String>[];
    for (final o in orders) {
      final c = Customer(name: o['name']!, phone: o['phone']!)
        ..nationalId = o['nid']!;
      c.id = await CustomerRepo.insert(c);
      final d = Device(customerId: c.id!, model: o['model']!)
        ..serial = o['serial']!;
      d.id = await DeviceRepo.insert(d);
      final code = await TicketRepo.nextCode();
      codes.add(code);
      final t = Ticket(
        code: code,
        customerId: c.id!,
        deviceId: d.id!,
        intakeDate: DateTime.now(),
        dueDate: tomorrow,
        dueTime: o['time']!,
        defect: o['defect']!,
        phoneState: o['state']!,
        estimateAmount: int.parse(o['estimate']!),
        depositAmount: int.parse(o['deposit']!),
        accessories: o['acc']!.isEmpty ? [] : [o['acc']!],
        termsAccepted: true,
      );
      t.id = await TicketRepo.insert(t);
      if (int.parse(o['deposit']!) > 0) {
        await PaymentRepo.insert(
            Payment(ticketId: t.id!, amount: int.parse(o['deposit']!), kind: 'deposit'));
      }
      await ReminderService.ensureForTicket(t, 3, 9);
    }

    final all = await TicketRepo.all();
    final tomorrowOrders = all
        .where((t) =>
            t.dueDate.year == tomorrow.year &&
            t.dueDate.month == tomorrow.month &&
            t.dueDate.day == tomorrow.day)
        .toList();
    expect(tomorrowOrders.length, 5);

    final ics = await CalendarExportService.buildIcs(
        includeDelivered: true, from: tomorrow, to: tomorrow);
    expect('BEGIN:VEVENT'.allMatches(ics).length, 5);
    expect(ics, contains('BEGIN:VTIMEZONE'));
    expect(ics, contains('TZID:Asia/Tehran'));
    expect(ics, contains('DTSTART;TZID=Asia/Tehran:${icsDay(tomorrow)}T080000'));
    expect(ics, contains('DTSTART;TZID=Asia/Tehran:${icsDay(tomorrow)}T120000'));
    expect(ics, contains('SUMMARY:تحویل ${codes.first} — علی رضایی'));
    expect(ics, contains('دستگاه: iPhone 13'));
    expect(ics, contains('BEGIN:VALARM'));

    // خروجی در مسیر موقت — قابل اجرا روی هر ماشین (نه فقط سندباکس توسعه)
    final out = File('${tempDir.path}/jsh_deliveries_farda.ics');
    await out.parent.create(recursive: true);
    await out.writeAsString(ics, flush: true);
    expect(await out.exists(), isTrue);
    expect(await out.length(), greaterThan(1000));
  });
}
