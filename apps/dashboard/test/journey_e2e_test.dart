/// تست اجرای واقعی سرتاسری — شبیه‌سازی سفر کامل کاربر طبق README
/// روی دیتابیس SQLite واقعی (sqflite_ffi) در مسیر موقت — بدون ساختگی بودن داده‌ها
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/assistant_service.dart';
import 'package:jsh_service_dashboard/core/services/backup_service.dart';
import 'package:jsh_service_dashboard/core/services/calendar_export_service.dart';
import 'package:jsh_service_dashboard/core/services/install_report_service.dart';
import 'package:jsh_service_dashboard/core/services/pdf_service.dart';
import 'package:jsh_service_dashboard/core/services/reminder_service.dart';
import 'package:jsh_service_dashboard/core/services/supervisor_service.dart';
import 'package:jsh_service_dashboard/core/utils.dart';
import 'package:jsh_service_dashboard/shared/data/holidays.dart';

/// path_provider بدون پلتفرم واقعی — مسیرهای موقت
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
    tempDir = await Directory.systemTemp.createTemp('jsh_e2e');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance(); // ساخت بانک واقعی
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('۱) بانک اطلاعاتی واقعی ساخته می‌شود', () async {
    final db = await Db.instance();
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    final names = tables.map((r) => r['name'] as String).toList();
    expect(names, containsAll(['customers', 'tickets', 'payments', 'reminders',
        'email_queue', 'license_state', 'audit_log', 'settings']));
  });

  test('۲) ویزارد فعال‌سازی: رضایت + ثبت محلی گزارش نصب (N-03)', () async {
    final state = await LicenseRepo.load();
    expect(state.installCount, 1); // نصب اول
    state.consentedAt = DateTime.now().toIso8601String();
    state.userEmail = 'shop@example.com';
    state.buyerName = 'فروشگاه تست';
    await LicenseRepo.save(state);
    await LicenseIntegrity.write();

    // وضعیت دروازه قبل از تکمیل باید «انتظار رضایت/ثبت» باشد
    final gate = InstallReportService.evaluateGate(
      consented: state.consentedAt.isNotEmpty,
      userEmail: state.userEmail,
      reportSent: state.reportSent,
      firstRunAt: state.firstRunAt,
      pendingReportAttempts: 0,
    );
    expect(gate, GateState.queueing); // تا ثبت گزارش اجرا نمی‌شود

    // ثبت محلی گزارش فعال‌سازی (نسخه 0.5.0 — بدون ایمیل)
    final path = await InstallReportService.writeReport(
      buyerName: state.buyerName,
      userEmail: state.userEmail,
      installCount: state.installCount,
      hardwareReport: 'تست سخت‌افزار',
    );
    final reportFile = File(path);
    expect(await reportFile.exists(), isTrue);
    final content = await reportFile.readAsString();
    expect(content, contains('فروشگاه تست'));
    expect(content, contains('نصب باقیمانده مجاز'));

    // علامت‌گذاری ثبت → دروازه راه‌اندازی باز می‌شود
    state.reportStatus = 'sent';
    state.reportSentAt = DateTime.now().toIso8601String();
    await LicenseRepo.save(state);
    await LicenseIntegrity.write();
    final gate2 = InstallReportService.evaluateGate(
      consented: state.consentedAt.isNotEmpty,
      userEmail: state.userEmail,
      reportSent: state.reportSent,
      firstRunAt: state.firstRunAt,
      pendingReportAttempts: 0,
    );
    expect(gate2, GateState.ok);
  });

  test('۳) پذیرش کامل: مشتری + دستگاه + سفارش + بیعانه + یادآوری', () async {
    final customer = Customer(name: 'علی رضایی', fatherName: 'حسن',
        nationalId: '1234567890', phone: '09131112233');
    customer.id = await CustomerRepo.insert(customer);

    final device = Device(customerId: customer.id!, model: 'iPhone 13',
        serial: 'F17GQ12345');
    device.id = await DeviceRepo.insert(device);

    final code = await TicketRepo.nextCode();
    expect(code, startsWith('RCP-'));
    final due = DateTime.now().add(const Duration(days: 10));
    final ticket = Ticket(
      code: code,
      customerId: customer.id!,
      deviceId: device.id!,
      intakeDate: DateTime.now(),
      dueDate: due,
      dueTime: '18:00',
      defect: 'تصویر نمی‌آید',
      estimateAmount: 500000,
      depositAmount: 100000,
      accessories: ['درب پشت', 'باتری'],
      termsAccepted: true,
    );
    ticket.id = await TicketRepo.insert(ticket);

    await PaymentRepo.insert(Payment(
        ticketId: ticket.id!, amount: 100000, kind: 'deposit'));

    final (lead, hour) = (3, 9);
    await ReminderService.ensureForTicket(ticket, lead, hour);
    final reminder = await ReminderRepo.forTicket(ticket.id!);
    expect(reminder, isNotNull);
    expect(reminder!.status, 'pending');

    // حسابرس: محاسبه قابل وصول = برآورد − پرداخت‌شده
    final paid = await PaymentRepo.paidSum(ticket.id!);
    expect(paid, 100000);
    final task = await ReminderService.buildTask(ticket);
    expect(task.collectable, 400000);
    expect(task.daysLeft, inInclusiveRange(8, 10));
  });

  test('۴) PDF رسید با سربرگ و امضا واقعاً ساخته می‌شود', () async {
    final tickets = await TicketRepo.all();
    final t = tickets.first;
    final c = (await CustomerRepo.byId(t.customerId))!;
    final d = (await DeviceRepo.byId(t.deviceId))!;
    final path = await PdfService.buildIntakeReceipt(
      shop: {'name': 'فروشگاه تست', 'address': 'رفسنجان', 'phone': '09130356250'},
      ticket: t,
      customer: c,
      device: d,
      signatureBytes: Uint8List.fromList([1, 2, 3]),
    );
    final f = File(path);
    expect(await f.exists(), isTrue);
    expect(await f.length(), greaterThan(1000));
  });

  test('۵) خروجی Google Calendar ICS معتبر است', () async {
    final path = await CalendarExportService.exportDeliveries();
    final content = await File(path).readAsString();
    expect(content, contains('BEGIN:VCALENDAR'));
    expect(content, contains('BEGIN:VEVENT'));
    expect(content, contains('X-WR-CALNAME'));
    expect(content, contains('SUMMARY:تحویل'));
  });

  test('۶) دستیار داخلی: کار روتین «پرینت فیش» و گزارش مالی', () async {
    final tickets = await TicketRepo.all();
    final code = tickets.first.code;
    final r1 = await AssistantService.handle('پرینت فیش شماره $code');
    expect(r1.text, contains('ساخته شد'));

    final r2 = await AssistantService.handle('چقدر قابل وصول داریم؟');
    expect(r2.text, contains('قابل وصول'));
  });

  test('۷) بک‌آپ دستی + بازیابی + حذف (قاعده ۹)', () async {
    final path = await BackupService.manualBackup();
    expect(await File(path).exists(), isTrue);
    final manuals = await BackupService.listManual();
    expect(manuals, isNotEmpty);

    await BackupService.restoreBackup(path); // باز و بسته شدن واقعی بانک
    final ticketsAfter = await TicketRepo.all();
    expect(ticketsAfter, isNotEmpty);

    // حذف با امنیت
    await BackupService.deleteBackup(path);
    expect(await File(path).exists(), isFalse);
  });

  test('۸) سوپروایزر: رمز نادرست رد می‌شود، درست باز می‌کند (قاعده ۱۲)', () async {
    expect(await SupervisorService.login('wrong-password'), isFalse);
    expect(SupervisorService.failCount, 1);
    // رمز واقعی فقط در پیام خصوصی به صاحب پروژه — اینجا از هش در می‌آوریم که پاس می‌شود
    expect(await SupervisorService.login('AvrinSegal!Super1405'), isTrue);
    expect(SupervisorService.active, isTrue);
    SupervisorService.logout();
    expect(SupervisorService.active, isFalse);
  });

  test('۹) پاک‌سازی کامل دیتابیس (فقط سوپروایزر) و خام شدن برنامه', () async {
    await BackupService.manualBackup(); // بک‌آپ اضطراری قبل پاک‌سازی
    await BackupService.wipeAllData();
    final customers = await CustomerRepo.search('');
    expect(customers, isEmpty);
    final settings = await SettingsRepo.all();
    expect(settings, isEmpty);
    // لایسنس باید باقی بماند تا دروازه N-03 بازهم کار کند
    final state = await LicenseRepo.load();
    expect(state.installCount, 1);
  });

  test('۱۰) ابزارها: رقم فارسی، مبلغ، تاریخ ۸ رقمی هوشمند، کبیسه', () {
    expect(money(1234567), '۱,۲۳۴,۵۶۷');
    expect(toEnglishDigits('۱۴۰۵'), '1405');
    final d = parseShamsi('1405/9/4');
    expect(d, isNotNull);
    // سال کبیسه ۱۴۰۳ — اسفند ۳۰ روزه (shamsi_date درست محاسبه می‌کند)
    expect(j.Jalali(1403, 12, 1).monthLength, 30);
    expect(j.Jalali(1404, 12, 1).monthLength, 29);
    // تعطیلات رسمی ثابت
    expect(holidayName(j.Jalali(1405, 1, 1)), isNotNull);
    expect(holidayName(j.Jalali(1405, 1, 13)), 'سیزده بدر');
    expect(holidayName(j.Jalali(1405, 5, 5)), isNull);
  });
}

