/// تست سرویس همگام‌سازی Google Sheet — منطق خالص ساخت ردیف (بدون بانک/شبکه)
import 'package:flutter_test/flutter_test.dart';

import 'package:jsh_service_dashboard/core/constants.dart';
import 'package:jsh_service_dashboard/core/services/sheet_sync_service.dart';
import 'package:jsh_service_dashboard/core/utils.dart';

void main() {
  test('ستون‌های شیت هماهنگ با ماژول پایتونی هستند (۱۲ ستون)', () {
    expect(SheetSyncConst.headers.length, 12);
    expect(
        SheetSyncConst.sheetId, '1UqbXVRUE0Fyf_CWS8Crr6mCGsEmSpvulLzt-IRoK6IQ');
    expect(SheetSyncConst.defaultTab, 'داشبورد تعمیرات و خدمات J.S.H');
  });

  test('ردیف: ارقام فارسی برای هزینه و تاریخ شمسی، انگلیسی برای شناسه و میلادی — قاعده ۱',
      () {
    final row = SheetSyncService.buildRow({
      'code': 'T-1001',
      'customer_name': 'علی رضایی',
      'phone': '09131234567',
      'device_model': 'iPhone 13',
      'defect': 'مشکل صفحه‌نمایش',
      'status': 'diagnosis',
      'estimate_amount': 2500000,
      'deposit_amount': 500000,
      'due_date': '2026-11-27',
      'created_at': '2026-11-26 10:30',
    }, 1,
        tomorrow: DateTime(2026, 11, 27));

    expect(row.length, 12);
    expect(row[0], 1); // شماره ردیف انگلیسی
    expect(row[1], 'T-1001'); // شناسه انگلیسی
    expect(row[3], "'09131234567"); // تلفن متنی — صفر حفظ می‌شود
    expect(row[6], contains('۱۴۰۵')); // تاریخ شمسی فارسی
    expect(row[7], '2026-11-27'); // میلادی انگلیسی
    expect(row[8], TicketStatus.labels['diagnosis']); // برچسب وضعیت فارسی
    expect(row[9], '۲,۵۰۰,۰۰۰'); // هزینه فارسی
    expect(row[10], contains('برگه فردا')); // سفارش فردا علامت می‌خورد
  });

  test('ردیف بدون بیعانه و بدون موعد فردا — یادداشت خالی', () {
    final row = SheetSyncService.buildRow({
      'code': 'T-1002',
      'customer_name': 'مریم احمدی',
      'phone': '',
      'device_model': 'Galaxy S21',
      'defect': 'شارژ نمی‌شود',
      'status': 'intake',
      'estimate_amount': 0,
      'deposit_amount': 0,
      'due_date': '2026-12-01',
      'created_at': '2026-11-26 12:00',
    }, 2,
        tomorrow: DateTime(2026, 11, 27));

    expect(row[9], ''); // هزینه صفر → خالی
    expect(row[10], ''); // یادداشت خالی
    expect(row[11], '2026-11-26 12:00'); // زمان ثبت حفظ شده
  });

  test('شماره تلفن بدون صفر ابتدایی دست‌نخورده می‌ماند', () {
    final row = SheetSyncService.buildRow({
      'code': 'T-1003',
      'customer_name': 'x',
      'phone': '9139999',
      'device_model': '',
      'defect': '',
      'status': 'ready',
      'estimate_amount': 100,
      'deposit_amount': 0,
      'due_date': '2026-12-05',
      'created_at': '',
    }, 3);
    expect(row[3], '9139999'); // بدون صفر → دست‌نخورده
    expect(row[8], TicketStatus.labels['ready']);
  });
}
