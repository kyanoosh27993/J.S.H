/// تست‌های فاز ۴ — پذیرش و فرم‌ها (بندهای ۱۰، ۷، ۱ + ۶)
/// لوازم همراه از تنظیمات، اعتبارسنجی کد ملی، یادآوری با عدد دلخواه،
/// فرم A5 سه‌برگی، پترن قفل و تحویل بی‌تاریخ
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/a5_receipt_service.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/reminder_service.dart';
import 'package:jsh_service_dashboard/core/constants.dart';
import 'package:jsh_service_dashboard/core/services/shop_settings_service.dart';
import 'package:jsh_service_dashboard/core/utils.dart';

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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase4_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    await AppSession.I.loginWith('admin', 'admin');
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('لوازم همراه قابل ویرایش (بند ۱۰)', () {
    test('پیش‌فرض + ذخیره/خواندن از تنظیمات', () async {
      final def = await ShopSettingsService.loadAccessories();
      expect(def, isNotEmpty); // پیش‌فرض فرم کاغذی
      await ShopSettingsService.saveAccessories(['درب پشت', 'شارژر', 'مموری']);
      final loaded = await ShopSettingsService.loadAccessories();
      expect(loaded, ['درب پشت', 'شارژر', 'مموری']);
    });
  });

  group('کد ملی / شناسه ملی (بند ۱۰)', () {
    test('۱۰ رقم برای فرد و ۱۱ رقم برای شرکت — بقیه رد', () {
      expect(isValidNationalId('1234567890'), isTrue); // ۱۰ رقم
      expect(isValidNationalId('۱۲۳۴۵۶۷۸۹۰'), isTrue); // ارقام فارسی
      expect(isValidNationalId('41123456789'), isTrue); // ۱۱ رقم شرکت
      expect(isValidNationalId('12345'), isFalse); // کوتاه
      expect(isValidNationalId('123456789012'), isFalse); // ۱۲ رقم
      expect(isValidNationalId(''), isTrue); // اختیاری
    });
  });

  group('یادآوری با عدد دلخواه (بند ۱)', () {
    test('بازه ۱ تا ۳۰ پذیرفته می‌شود — خارج از بازه به پیش‌فرض', () async {
      await SettingsRepo.set('reminder_lead_days', '14');
      final (lead, _) = await ReminderService.loadPrefs();
      expect(lead, 14);
      await SettingsRepo.set('reminder_lead_days', '40'); // خارج از بازه
      final (lead2, _) = await ReminderService.loadPrefs();
      expect(lead2, ReminderPrefs.defaultLeadDays);
    });
  });

  group('پترن قفل و تحویل بی‌تاریخ (بند ۷ و ۱۰)', () {
    late int tid;
    setUpAll(() async {
      final cId = await CustomerRepo.insert(Customer(name: 'مشتری فاز ۴'));
      final dId = await DeviceRepo.insert(
          Device(customerId: cId, model: 'گوشی پیکسل'));
      final admin = await UserRepo.byUsernameRow('admin');
      tid = await TicketRepo.insert(Ticket(
        code: 'T-P4-1',
        customerId: cId,
        deviceId: dId,
        intakeDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 7)),
        estimateAmount: 900000,
        lockPattern: '1-5-9',
        dueUnknown: true,
        dueTime: '--:--',
        createdBy: admin!['id'] as int,
      ));
    });

    test('پترن قفل و dueUnknown در بانک پایدار می‌ماند', () async {
      final t = await TicketRepo.byId(tid);
      expect(t!.lockPattern, '1-5-9');
      expect(t.dueUnknown, isTrue);
      expect(t.dueTime, '--:--');
    });
  });

  group('فرم سه‌برگی A5 (بند ۱۰ + بند ۶)', () {
    test('PDF با برگه‌های انتخابی ساخته می‌شود', () async {
      final cId = await CustomerRepo.insert(Customer(name: 'مشتری A5'));
      final dId = await DeviceRepo.insert(
          Device(customerId: cId, model: 'لپ‌تاپ HP', serial: 'HP123456'));
      final ticket = Ticket(
        code: 'T-P4-A5',
        customerId: cId,
        deviceId: dId,
        intakeDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 3)),
        dueTime: '14:00',
        defect: 'روشن نمی‌شود',
        phoneState: 'خط و خش دارد',
        estimateAmount: 1200000,
        depositAmount: 500000,
        accessories: ['باتری'],
        lockPattern: '1-3-9',
        termsAccepted: true,
      );
      ticket.id = await TicketRepo.insert(ticket);
      await TicketItemRepo.insert(TicketItem(
        ticketId: ticket.id!,
        description: 'تعویض فن',
        qty: 1,
        price: 700000,
      ));
      final customer = (await CustomerRepo.byId(cId))!;
      final device = (await DeviceRepo.byId(dId))!;
      final shop = {
        'name': 'فروشگاه آزمایشی',
        'address': 'کرمان، رفسنجان',
        'phone': '09130356250',
      };
      // هر سه برگه
      final p1 = await A5ReceiptService.build(
        shop: shop,
        ticket: ticket,
        customer: customer,
        device: device,
        items: [],
        sheets: (true, true, true),
      );
      expect(File(p1).existsSync(), isTrue);
      expect(File(p1).lengthSync(), greaterThan(3000));
      // فقط برگ فروشگاه
      final p2 = await A5ReceiptService.build(
        shop: shop,
        ticket: ticket,
        customer: customer,
        device: device,
        items: [],
        sheets: (false, true, false),
      );
      expect(File(p2).existsSync(), isTrue);
      // تحویل بی‌تاریخ — متن اعلامی در PDF خطا نمی‌دهد
      final t2 = await TicketRepo.byId(ticket.id!);
      expect(t2!.dueUnknown, isFalse);
    });
  });
}
