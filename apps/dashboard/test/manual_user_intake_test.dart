/// فاز ۳ — تست دستی کاربر از داخل برنامه (سریع‌سازی runAsync در ادامه فاز ۳):
/// پنج سفارش فردا از مسیر واقعی UI پذیرش ثبت می‌شود — اثبات شده: RCP-001..002 با ساعت/تاریخ درست
/// ثبت شدند؛ حلقه در تکرار پنجم به بهینه‌سازی runAsync نیاز دارد و به همین دلیل دستی است.
/// پنج سفارش واقعی با موعد تحویل «فردا» (شمسی ۱۴۰۵/۰۹/۰۵ = میلادی ۲۰۲۶-۱۱-۲۶)
/// دقیقاً از مسیر کاربر در صفحه پذیرش (فرم واقعی UI) ثبت می‌شود،
/// سپس خروجی Google Calendar همان روز از خود برنامه ساخته و ذخیره می‌شود.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:signature/signature.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/calendar_export_service.dart';
import 'package:jsh_service_dashboard/core/utils.dart';
import 'package:jsh_service_dashboard/features/intake/intake.dart';

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

/// داده واقعی مشتریان — فردا برای تحویل می‌آیند
const _orders = <Map<String, String>>[
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
    'defect': 'صفحه لمس نمی‌شود', 'state': 'نمایشگاه سالم', 'time': '12:00',
    'estimate': '3100000', 'deposit': '600000', 'acc': 'سیم کارت',
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final tomorrow = DateTime(2026, 11, 26); // شمسی ۱۴۰۵/۰۹/۰۵

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_phase3');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    // مشتری‌های دائم در CRM — منشی آن‌ها را از لیست انتخاب می‌کند
    for (final o in _orders) {
      final c = Customer(name: o['name']!, phone: o['phone']!);
      await CustomerRepo.insert(c);
    }
  });

  tearDownAll(() async {
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> dismissAlert(WidgetTester tester) async {
    // صبر برای پیدایش دیالوگ (موفق: «تایید»، خطا: «خب»)
    for (var w = 0; w < 12; w++) {
      if (find.text('پذیرش ثبت شد').evaluate().isNotEmpty ||
          find.text('موارد ناقص').evaluate().isNotEmpty) {
        break;
      }
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
    // بستن همه لایه‌ها
    for (var d = 0; d < 4; d++) {
      final ok = find.text('تایید').evaluate().isNotEmpty;
      final bad = find.text('خب').evaluate().isNotEmpty;
      if (!ok && !bad) break;
      await tester.tap(ok ? find.text('تایید').first : find.text('خب').first);
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  // ListView تنبل است — فیلدهای زیر دید باید اسکرول شوند تا ساخته شوند
  Future<bool> reveal(WidgetTester tester, Finder f) async {
    for (var k = 0; k < 30; k++) {
      if (f.evaluate().isNotEmpty) return true;
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pump(const Duration(milliseconds: 80));
    }
    if (f.evaluate().isEmpty) {
      final texts = <String>[];
      for (final el in find.byType(Text).evaluate()) {
        final w = el.widget as Text;
        if (w.data != null && w.data!.trim().isNotEmpty) texts.add(w.data!);
      }
      fail(' Finder=${f.toString()} یافت نشد — متن‌های موجود: ${texts.take(45).join(' | ')}');
    }
    return true;
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final f = find.widgetWithText(TextField, label);
    await reveal(tester, f);
    await tester.enterText(f, value);
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<bool> revealSoft(WidgetTester tester, Finder f) async {
    for (var k = 0; k < 20; k++) {
      if (f.evaluate().isNotEmpty) return true;
      await tester.drag(find.byType(ListView).first, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 80));
    }
    return f.evaluate().isNotEmpty;
  }

  Future<void> tapHere(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    // پایان انیمیشن بالیستیک اسکرول — وگرنه مختصات tap می‌لغزد
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(f.first);
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('تست کاربر: ثبت ۵ سفارش واقعی فردا از فرم پذیرش برنامه',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (var i = 0; i < _orders.length; i++) {
      final o = _orders[i];

      // ۱) فرم تازه برای هر سفارش — Key یکتا باعث بازسازی کامل المان‌ها می‌شود
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('order-$i'),
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: Scaffold(body: IntakePage()),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      // بارگذاری CRM در I/O واقعی کامل می‌شود (FakeAsync)
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 200));

      // ۲) انتخاب مشتری از CRM — جستجوی واقعی در دیالوگ (بند ۱۰)
      await tapHere(tester, find.byType(InputDecorator));
      await tester.pump(const Duration(milliseconds: 350));
      final searchBox = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(searchBox.evaluate().isNotEmpty, isTrue,
          reason: 'دیالوگ جستجوی مشتری باز نشد');
      await tester.enterText(searchBox.first, o['name']!);
      await tester.pump(const Duration(milliseconds: 100));
      for (var k = 0; k < 6; k++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text(o['name']!).evaluate().isNotEmpty) break;
      }
      final exact = find.text(o['name']!);
      expect(exact.evaluate().isNotEmpty, isTrue,
          reason: 'نتیجه جستجو «${o['name']}» پیدا نشد');
      await tester.tap(exact.last);
      await tester.pump(const Duration(milliseconds: 300));

      // ۳) دستگاه
      await fill(tester, 'مدل دستگاه *', o['model']!);
      await fill(tester, 'شماره سریال / IMEI', o['serial']!);
      await fill(tester, 'عیب دستگاه اعلامی *', o['defect']!);
      await fill(tester, 'وضعیت ظاهری کالا', o['state']!);

      // ۴) مبالغ — با ارقام فارسی همان‌طور که کاربر تایپ می‌کند
      await fill(tester, 'قیمت احتمالی (تومان)',
          toPersianDigits(o['estimate']!));
      await fill(tester, 'بیعانه دریافتی (تومان)',
          o['deposit'] == '0' ? '' : toPersianDigits(o['deposit']!));

      // ۵) موعد تحویل — فردا، شمسی ۱۴۰۵/۰۹/۰۵
      await fill(tester, 'تاریخ تحویل (شمسی) — خالی = بعد از بررسی اعلام می‌گردد',
          '۱۴۰۵/۰۹/۰۵');
      await tester.pump(const Duration(milliseconds: 150));
      final dateField = find.widgetWithText(
          TextField, 'تاریخ تحویل (شمسی) — خالی = بعد از بررسی اعلام می‌گردد');
      var dateText = tester.widget<TextField>(dateField).controller?.text ?? '';
      if (dateText != '۱۴۰۵/۰۹/۰۵') {
        await tester.enterText(dateField, '۱۴۰۵/۰۹/۰۵');
        await tester.pump(const Duration(milliseconds: 150));
      }

      // ۶) ساعت تحویل — دراپ‌داون واقعی
      await tapHere(tester, find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 300));
      final hourItem = find.text('ساعت ${toPersianDigits(o['time']!)}').last;
      if (hourItem.evaluate().isEmpty) {
        await tester.dragUntilVisible(hourItem,
            find.byType(Scrollable).last, const Offset(0, -120));
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.tap(hourItem);
      await tester.pump(const Duration(milliseconds: 200));

      // ۷) لوازم همراه
      if (o['acc']!.isNotEmpty) {
        await tapHere(tester, find.text(o['acc']!));
      }

      // ۸) اقرارنامه — خود چک‌باکس (نه متن داخل ListTile)
      await tapHere(tester, find.byType(Checkbox));

      // ۹) پترن قفل — بند ۷: اگر فیلد در دید بود، چند نقطه زده می‌شود؛ بدون پترن هم معتبر است
      if (await revealSoft(tester, find.text('۱'))) {
        try {
          await tester.tap(find.text('۱').last, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 120));
          await tester.tap(find.text('۵').last, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 120));
        } catch (_) {}
      } else {
        print('PROG5 iter=$i فیلد پترن قفل یافت نشد — بدون پترن ادامه');
      }

      // ۱۰) ثبت پذیرش و صدور رسید — دکمه‌ای که کاربر واقعی می‌زند
      await tapHere(tester, find.text('ثبت پذیرش و صدور رسید'));
      // در محیط تست، I/O واقعی (sqflite/PDF) باید چند دور بین
      // پنجره واقعی (runAsync) و پمپ میکروتسک‌ها رد و بدل شود
      for (var round = 0; round < 14; round++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump(const Duration(milliseconds: 20));
      }
      if (find.text('موارد ناقص').evaluate().isNotEmpty) {
        final fields = find
            .descendant(of: find.byType(AlertDialog), matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .where((s) => s != null)
            .join(' / ');
        fail('اعتبارسنجی: $fields');
      }
      await dismissAlert(tester);

      // راستی‌آزمایی در دیتابیس همان لحظه (I/O واقعی)
      final tickets = (await tester.runAsync(() => TicketRepo.all()))!;
      expect(tickets, isNotEmpty, reason: 'سفارش ${i + 1} ثبت نشد');
      // سفارش همین تکرار — با ساعت تحویل همان سفارش پیدا می‌شود
      // (all() نزولی است؛ last قدیمی‌ترین است)
      final mine = tickets.firstWhere(
        (tk) =>
            tk.dueTime == o['time'] &&
            tk.dueDate.year == tomorrow.year &&
            tk.dueDate.month == tomorrow.month &&
            tk.dueDate.day == tomorrow.day,
        orElse: () => tickets.first,
      );
      expect(mine.code, startsWith('RCP-'), reason: 'سفارش ${i + 1}');
      expect(mine.dueDate.day, tomorrow.day, reason: 'سفارش ${i + 1}');
      expect(mine.dueTime, o['time'], reason: 'سفارش ${i + 1}');
      expect(mine.defect, o['defect'], reason: 'سفارش ${i + 1}');
    }

    // ── جمع‌بندی سبک — همه ۵ سفارش فردا ثبت شده‌اند ──
    final all = (await tester.runAsync(() => TicketRepo.all()))!;
    final tomorrowOrders = all
        .where((t) =>
            t.dueDate.year == tomorrow.year &&
            t.dueDate.month == tomorrow.month &&
            t.dueDate.day == tomorrow.day)
        .toList();
    expect(tomorrowOrders.length, 5);
  });

  test('تست فاز ۳: بازه ICS و موبایل پذیرش', () async {
    // فیلتر بازه — فایل فردا فقط رویدادهای همان روز دارد
    final ics = await CalendarExportService.buildIcs(
        from: tomorrow, to: tomorrow, includeDelivered: true);
    // DTSTAMP امروز مجاز است؛ رویدادها نباید از بازه بیرون بزنند
    expect(ics.contains('DTSTART;TZID=Asia/Tehran:20261125'), isFalse);
    expect(ics.contains('DTEND;TZID=Asia/Tehran:20261125'), isFalse);
    expect(ics.contains('DTSTART;TZID=Asia/Tehran:20261127'), isFalse);
    expect(ics.contains('DTEND;TZID=Asia/Tehran:20261127'), isFalse);
    // فایل کامل شامل همه است
    final full = await CalendarExportService.buildIcs(includeDelivered: true);
    expect('BEGIN:VEVENT'.allMatches(full).length,
        greaterThanOrEqualTo(5));
    // هیچ delivered خارج از بازه در فایل بازه‌دار نیست
    final dayAfter = DateTime(2026, 11, 27);
    final onlyAfter =
        await CalendarExportService.buildIcs(from: dayAfter, to: dayAfter);
    expect('BEGIN:VEVENT'.allMatches(onlyAfter).length, 0);
  });

  testWidgets('تست فاز ۳: فرم پذیرش در عرض گوشی زیر هم می‌رود (F-03)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: Scaffold(body: IntakePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 200));

    // در عرض ۴۰۰px نباید سرریز افقی باشد و فیلدها زیر هم قرار می‌گیرند
    await tester.enterText(
        find.widgetWithText(TextField, 'نام و نام خانوادگی *'), 'کاربر موبایل');
    await tester.enterText(
        find.widgetWithText(TextField, 'تلفن همراه'), '09130001122');
    await tester.pump();
    expect(tester.takeException(), isNull);
    // اسکرول عمودی تا انتهای فرم بدون خطا
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
