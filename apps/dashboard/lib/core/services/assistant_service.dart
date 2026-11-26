/// هوش مصنوعی داخلی آفلاین — قاعده ۸
/// موتور درک دستورهای فارسی + اجرای کارهای روتین به‌صورت خودکار.
/// پاسخ‌ها فقط از دیتابیس محلی ساخته می‌شوند — بدون اینترنت و بدون سرویس بیرونی.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models.dart';
import '../repos.dart';
import '../utils.dart';
import 'backup_service.dart';
import 'daily_report_service.dart';
import '../db/db.dart';
import 'pdf_service.dart';
import 'forecast_service.dart';
import 'reminder_service.dart';
import '../warranty.dart';

class AssistantAction {
  final String label;
  final String routeKey;
  const AssistantAction(this.label, this.routeKey);
}

class AssistantReply {
  final String text;
  final List<AssistantAction> actions;
  const AssistantReply(this.text, {this.actions = const []});
}

class AssistantService {
  /// پردازش پیام کاربر — درک زبان طبیعی فارسی ساده + اجرای عملیات
  static Future<AssistantReply> handle(String input) async {
    final text = toEnglishDigits(input.trim()).toLowerCase();
    if (text.isEmpty) {
      return const AssistantReply('دستوری بنویسید. مثال: «پرینت فیش شماره RCP-14050904-001»');
    }

    // ── کارهای روتین خودکار ──
    // «پرینت فیش شماره X» / «چاپ رسید X» / «فیش X»
    final printMatch = RegExp(r'(پرینت|چاپ|فیش|رسید)\D*?(rcp-\d+-\d+|\d{4,})')
        .firstMatch(text);
    if (printMatch != null) {
      return _printReceipt(printMatch.group(2)!);
    }

    // «وضعیت سفارش X» / «سفارش X»
    final statusMatch =
        RegExp(r'وضعیت|سفارش|پیگیری').hasMatch(text) ? _codeIn(text) : null;
    if (statusMatch != null) return _ticketStatus(statusMatch);

    // «بدهی/باقیمانده X» یا «بدهی من چقدره»
    if (text.contains('بدهی') || text.contains('باقیمانده') ||
        text.contains('قابل وصول')) {
      final code = _codeIn(text);
      if (code != null) return _ticketBalance(code);
      return _receivablesSummary();
    }

    // «بک آپ» / «پشتیبان»
    if (text.contains('بک') || text.contains('پشتیبان')) {
      if (text.contains('بگیر') || text.contains('بساز') || text.contains('انجام')) {
        final path = await BackupService.manualBackup();
        return AssistantReply(
          'بک‌آپ کامل گرفته شد و ذخیره شد:\n$path',
        );
      }
      final autos = await BackupService.listAuto();
      final manuals = await BackupService.listManual();
      return AssistantReply(
        'بک‌آپ‌ها: ${toPersianDigits('${manuals.length}')} بک‌آپ دستی و '
        '${toPersianDigits('${autos.length}')} بک‌آپ اتوماتیک موجود است. '
        'بک‌آپ‌های اتوماتیک بعد از ۳۰ روز خودکار پاک می‌شوند. برای بازیابی به ماژول «مدیریت دیتابیس» بروید.',
      );
    }

    // «یادآوری» / «امروز چی باید تحویل بشه»
    if (text.contains('یادآور') || text.contains('یادآوری') ||
        text.contains('امروز') && text.contains('تحویل')) {
      return _todayDeliveries();
    }

    // «فروش/درآمد امروز/این ماه»
    if (text.contains('فروش') || text.contains('درآمد')) {
      return _revenueSummary(text);
    }

    // فاز ۲: گارانتی
    if (text.contains('گارانتی')) {
      final code = _codeIn(text);
      if (code != null) return _warrantyInfo(code);
      return _warrantySummary();
    }

    // فاز ۲: پیش‌بینی فروش
    if (text.contains('پیش') && text.contains('بینی') || text.contains('پیش بینی')) {
      return _forecastSummary();
    }

    // فاز ۷ — بند ۹: گزارش روزانه، ابطالی‌ها، عملکرد کاربران
    if (text.contains('گزارش') && (text.contains('امروز') || text.contains('دیروز') || text.contains('روز'))) {
      return _dailyReportSummary(text.contains('دیروز'));
    }
    if (text.contains('ابطال')) {
      return _cancelledSummary();
    }
    if (text.contains('عملکرد') || text.contains('کاربران') && text.contains('گزارش')) {
      return _userPerformanceSummary();
    }

    // راهنما
    if (text.contains('بدهکار')) {
      return _receivablesSummary();
    }

    // راهنما
    return const AssistantReply(
      'کارهایی که می‌توانم انجام بدهم:\n'
      '• «پرینت فیش شماره RCP-14050904-001» — ساخت PDF رسید و باز شدن برای چاپ\n'
      '• «وضعیت سفارش RCP-14050904-001»\n'
      '• «بدهی RCP-14050904-001» یا «چقدر قابل وصول داریم؟»\n'
      '• «بک‌آپ بگیر» — پشتیبان کامل و بی‌درنگ\n'
      '• «یادآوری‌های امروز»\n'
      '• «فروش این ماه» / «درآمد امروز»\n'
      'همه پاسخ‌ها از دیتابیس محلی خود برنامه ساخته می‌شود؛ بدون نیاز به اینترنت.',
    );
  }

  static String? _codeIn(String text) {
    final m = RegExp(r'rcp-\d+-\d+').firstMatch(text);
    if (m != null) return m.group(0)!.toUpperCase();
    return null;
  }

  static Future<AssistantReply> _printReceipt(String code) async {
    final wanted = code.toUpperCase();
    final tickets = await TicketRepo.all();
    Ticket? ticket;
    for (final t in tickets) {
      if (t.code.toUpperCase() == wanted) {
        ticket = t;
        break;
      }
    }
    if (ticket == null) {
      return AssistantReply('سفارشی با شماره «$code» پیدا نشد. شماره را از کارتابل چک کنید.');
    }
    final c = (await CustomerRepo.byId(ticket.customerId))!;
    final d = (await DeviceRepo.byId(ticket.deviceId))!;
    final shop = await SettingsRepo.all();
    final path = await PdfService.buildIntakeReceipt(
      shop: shop,
      ticket: ticket,
      customer: c,
      device: d,
      signatureBytes: ticket.signaturePath.isNotEmpty &&
              File(ticket.signaturePath).existsSync()
          ? File(ticket.signaturePath).readAsBytesSync()
          : Uint8List(0),
    );
    // باز شدن خودکار با نمایشگر PDF پیش‌فرض → آماده چاپ
    try {
      if (Platform.isWindows) {
        await ProcessLauncher.start('cmd', ['/c', 'start', '', path]);
      } else {
        await ProcessLauncher.start('xdg-open', [path]);
      }
    } catch (_) {}
    return AssistantReply(
      'فیش ${ticket.code} ساخته شد و برای چاپ باز شد:\n'
      '${p.basename(path)}\nمشتری: ${c.name} — موعد: ${shamsiDate(ticket.dueDate)}',
    );
  }

  static Future<AssistantReply> _ticketStatus(String code) async {
    final tickets = await TicketRepo.all();
    Ticket? ticket;
    for (final t in tickets) {
      if (t.code.toUpperCase() == code) {
        ticket = t;
        break;
      }
    }
    if (ticket == null) return AssistantReply('سفارش «$code» پیدا نشد.');
    final c = (await CustomerRepo.byId(ticket.customerId))!;
    final items = await TicketItemRepo.byTicket(ticket.id!);
    final itemsSum = items.fold<int>(0, (s, i) => s + i.price * i.qty);
    final paid = await PaymentRepo.paidSum(ticket.id!);
    final total = itemsSum > 0 ? itemsSum : ticket.estimateAmount;
    return AssistantReply(
      'سفارش ${ticket.code} — ${statusLabel(ticket.status)}\n'
      'مشتری: ${c.name} — موعد تحویل: ${shamsiDate(ticket.dueDate)} ساعت ${ticket.dueTime}\n'
      'جمع فاکتور: ${moneyToman(total)} — پرداخت‌شده: ${moneyToman(paid)} — '
      'باقیمانده: ${moneyToman(total - paid)}',
      actions: [const AssistantAction('باز کردن سفارش', 'ticket')],
    );
  }

  static Future<AssistantReply> _ticketBalance(String code) async {
    final tickets = await TicketRepo.all();
    Ticket? ticket;
    for (final t in tickets) {
      if (t.code.toUpperCase() == code) {
        ticket = t;
        break;
      }
    }
    if (ticket == null) return AssistantReply('سفارش «$code» پیدا نشد.');
    final items = await TicketItemRepo.byTicket(ticket.id!);
    final itemsSum = items.fold<int>(0, (s, i) => s + i.price * i.qty);
    final paid = await PaymentRepo.paidSum(ticket.id!);
    final total = itemsSum > 0 ? itemsSum : ticket.estimateAmount;
    final added = ReminderService.addedOf(ticket, items);
    return AssistantReply(
      'مستند مالی ${ticket.code}:\n'
      'جمع: ${moneyToman(total)} — بیعانه: ${moneyToman(ticket.depositAmount)} — '
      'مبلغ افزوده نسبت به برآورد: ${moneyToman(added)} — '
      'قابل وصول: ${moneyToman(total - paid)}',
    );
  }

  static Future<AssistantReply> _receivablesSummary() async {
    final tickets = await TicketRepo.all();
    var sum = 0;
    var count = 0;
    final lines = <String>[];
    for (final t in tickets) {
      if (t.status == 'delivered') continue;
      final items = await TicketItemRepo.byTicket(t.id!);
      final itemsSum = items.fold<int>(0, (s, i) => s + i.price * i.qty);
      final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
      final paid = await PaymentRepo.paidSum(t.id!);
      final rem = total - paid;
      if (rem > 0) {
        count++;
        sum += rem;
        if (lines.length < 6) lines.add('${t.code}: ${moneyToman(rem)}');
      }
    }
    return AssistantReply(
      count == 0
          ? 'هیچ طلب بازگشتی از سفارش‌های باز وجود ندارد.'
          : '${toPersianDigits('$count')} سفارش باز با جمع قابل وصول ${moneyToman(sum)}:\n'
              '${lines.join('\n')}',
    );
  }

  static Future<AssistantReply> _todayDeliveries() async {
    final now = DateTime.now();
    final due = await TicketRepo.dueBetween(now, now.add(const Duration(days: 1)));
    if (due.isEmpty) return const AssistantReply('برای امروز سفارش در انتظار تحویلی نیست.');
    final lines = <String>[];
    for (final t in due) {
      final c = (await CustomerRepo.byId(t.customerId))!;
      lines.add('${t.code} — ${c.name} — ساعت ${t.dueTime} — ${statusLabel(t.status)}');
    }
    return AssistantReply(
      '${toPersianDigits('${due.length}')} سفارش امروز باید تحویل شود:\n${lines.join('\n')}',
    );
  }

  static Future<AssistantReply> _revenueSummary(String text) async {
    final now = DateTime.now();
    final isToday = text.contains('امروز');
    final tickets = await TicketRepo.all();
    var revenue = 0;
    var n = 0;
    for (final t in tickets) {
      if (t.status != 'delivered') continue;
      final at = DateTime.tryParse(t.updatedAt) ?? now;
      final match = isToday
          ? (at.year == now.year && at.month == now.month && at.day == now.day)
          : (at.year == now.year && at.month == now.month);
      if (!match) continue;
      final items = await TicketItemRepo.byTicket(t.id!);
      revenue += items.fold<int>(0, (s, i) => s + i.price * i.qty);
      n++;
    }
    return AssistantReply(
      '${isToday ? 'درآمد امروز' : 'درآمد این ماه'}: ${moneyToman(revenue)} '
      'از ${toPersianDigits('$n')} سفارش تحویل‌شده.',
    );
  }
  static Future<AssistantReply> _warrantyInfo(String code) async {
    final tickets = await TicketRepo.all();
    Ticket? ticket;
    for (final t in tickets) {
      if (t.code.toUpperCase() == code.toUpperCase()) {
        ticket = t;
        break;
      }
    }
    if (ticket == null) return AssistantReply('سفارش «$code» پیدا نشد.');
    final w = await WarrantyRepo.forTicket(ticket.id!);
    if (w == null) {
      return AssistantReply('برای ${ticket.code} گارانتی ثبت نشده — با تحویل، خودکار ساخته می‌شود.');
    }
    final days = w.endDate.difference(DateTime.now()).inDays;
    return AssistantReply(
      'گارانتی ${ticket.code}: تا ${shamsiDate(w.endDate)} '
      '(${days >= 0 ? '${toPersianDigits('$days')} روز باقی‌مانده' : 'منقضی شده'}) — '
      'مجموع ${toPersianDigits('${w.months}')} ماه. برای تمدید به ماژول گارانتی بروید.',
    );
  }

  static Future<AssistantReply> _warrantySummary() async {
    final all = await WarrantyRepo.all();
    var active = 0, expiring = 0, expired = 0;
    for (final w in all) {
      switch (w.liveStatus()) {
        case 'active':
          active++;
          break;
        case 'expiring':
          expiring++;
          break;
        default:
          expired++;
      }
    }
    return AssistantReply(
      'گارانتی‌ها: ${toPersianDigits('$active')} فعال، '
      '${toPersianDigits('$expiring')} نزدیک انقضا (۳۰ روز پایانی)، '
      '${toPersianDigits('$expired')} منقضی. ماژول گارانتی را ببینید.',
    );
  }

  static Future<AssistantReply> _forecastSummary() async {
    final future = await ForecastService.forecast(months: 3);
    final total = future.fold<double>(0, (s, e) => s + e.value);
    return AssistantReply(
      'پیش‌بینی صادقانه (میانگین متحرک ۳ ماه گذشته): '
      'درآمد تقریبی هر یک از ۳ ماه آینده حدود ${moneyToman(total ~/ 3)} تومان است. '
      'نمودار خطی داشبورد همین پیش‌بینی را با خط‌چین نشان می‌دهد.',
    );
  }
  // ── فاز ۷ — بند ۹: پاسخ‌های هوشمند بر پایه داده جدید ──

  static Future<AssistantReply> _dailyReportSummary(bool yesterday) async {
    final day = DateTime.now().subtract(Duration(days: yesterday ? 1 : 0));
    final events = await DailyReportService.eventsOf(day);
    final byCat = <String, int>{};
    for (final e in events) {
      byCat[e.category] = (byCat[e.category] ?? 0) + 1;
    }
    final parts = [
      for (final e in byCat.entries) '${e.key}: ${toPersianDigits('${e.value}')}',
    ];
    return AssistantReply(
      'گزارش ${yesterday ? 'دیروز' : 'امروز'} — ${toPersianDigits('${events.length}')} رخداد:\n'
      '${parts.isEmpty ? 'رخدادی ثبت نشده است.' : parts.join('، ')}\n'
      'برای دیدن جزئیات و خروجی فایل: صفحه «یادآوری‌ها → گزارش روزانه».',
    );
  }

  static Future<AssistantReply> _cancelledSummary() async {
    final db = await Db.instance();
    final rows = await db.query('invoices',
        where: 'status = ?', whereArgs: ['cancelled'], orderBy: 'id DESC', limit: 10);
    if (rows.isEmpty) {
      return const AssistantReply('هیچ سند ابطالی ثبت نشده است.');
    }
    final lines = [
      for (final r in rows)
        '${toPersianDigits((r['number'] ?? '') as String)} — '
            '${DailyReportService.moneyFa(((r['total'] ?? 0) as int))} تومان'
            '${((r['cancel_reason'] ?? '') as String).isEmpty ? '' : ' — دلیل: ${(r['cancel_reason'] ?? '') as String}'}',
    ];
    return AssistantReply(
      '${toPersianDigits('${rows.length}')} سند ابطالی اخیر:\n${lines.join('\n')}\n'
      '(لیست کامل: صفحه «فاکتورها → ابطال‌شده‌ها»)',
    );
  }

  static Future<AssistantReply> _userPerformanceSummary() async {
    final now = DateTime.now();
    final rows = await TicketRepo.activityReport(
        now.subtract(const Duration(days: 30)).toIso8601String(),
        now.add(const Duration(days: 1)).toIso8601String());
    final lines = [
      for (final r in rows)
        '${((r['display_name'] ?? '') as String).isEmpty ? r['username'] : r['display_name']}: '
            '${toPersianDigits('${r['intakes']}')} پذیرش، '
            '${toPersianDigits('${r['delivered']}')} تحویل، '
            'وصولی ${DailyReportService.moneyFa(((r['collected'] ?? 0) as int))} تومان '
            '(${toPersianDigits((((r['share'] ?? 0.0) as num).toDouble().toStringAsFixed(0)))}٪ سهم)',
    ];
    return AssistantReply(
      'عملکرد کاربران در ۳۰ روز اخیر:\n${lines.join('\n')}',
    );
  }
}

/// لفاف Process برای تست‌پذیری (در تست میزبان باز شدن PDF نادیده گرفته می‌شود)
class ProcessLauncher {
  static Future<dynamic> start(String exe, List<String> args) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return Process.start(exe, args);
    }
    return null;
  }
}
