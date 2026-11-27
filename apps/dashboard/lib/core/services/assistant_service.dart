/// هوش مصنوعی داخلی آفلاین — قاعده ۸ + فاز ۷ (بند ۱۶)
/// موتور درک نیت (Intent Engine) برای زبان طبیعی فارسی + اجرای کارهای روتین.
/// پاسخ‌ها فقط از دیتابیس محلی ساخته می‌شوند — بدون اینترنت و بدون سرویس بیرونی.
/// لایه قدیمی «دستور ثابت» به‌صورت اجراکننده نیت‌ها حفظ شده تا هیچ دستور فعلی
/// از کار نیفتد (سازگاری رو به عقب).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models.dart';
import '../repos.dart';
import '../utils.dart';
import '../db/db.dart';
import 'app_session.dart';
import 'auth_service.dart';
import 'backup_service.dart';
import 'daily_report_service.dart';
import 'home_stats_service.dart';
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

/// گزینه شفاف‌سازی — اجرای انتخاب کاربر با شماره یا نام (بند ۱۶)
class _Opt {
  final String label;
  final Future<AssistantReply> Function() run;
  const _Opt(this.label, this.run);
}

/// یک نیت از کاتالوگ نیت‌ها — شناسه، برچسب فارسی و کلیدواژه‌های تشخیص
class AssistantIntent {
  final String id;
  final String title;
  final List<String> keywords;
  const AssistantIntent(this.id, this.title, this.keywords);
}

class AssistantService {
  /// حافظه کوتاه‌مدت گزینه‌ها — «شماره ۲» گزینه دوم آخرین سوال را اجرا می‌کند
  static List<_Opt> _lastOptions = const [];
  static String _lastNorm = '';

  // ─────────────────────────────────────────────────────────────────────────
  // کاتالوگ نیت‌ها (بند ۱۶) — ترتیب فهرست، اولویت تساوی امتیاز را تعیین می‌کند
  // ─────────────────────────────────────────────────────────────────────────
  static const List<AssistantIntent> _intents = [
    AssistantIntent('print_receipt', 'پرینت فیش رسید', ['پرینت', 'چاپ', 'فیش', 'رسید']),
    AssistantIntent('order_status', 'وضعیت سفارش', ['وضعیت', 'پیگیری', 'کجاست', 'چی شده', 'سفارش']),
    AssistantIntent('orders_summary', 'خلاصه سفارش‌ها', ['خلاصه', 'تعداد', 'سفارش های', 'سفارش های باز', 'گزارش سفارش']),
    AssistantIntent('reminders', 'یادآوری‌های امروز/فردا', ['یادآوری', 'یادآور', 'یاداوری', 'یاداور', 'موعد', 'تحویل امروز', 'تحویل فردا', 'کارهای فردا', 'فردا', 'باید تحویل']),
    AssistantIntent('finance', 'مالی و فروش', ['فروش', 'درآمد', 'سود', 'خالص', 'تخفیف', 'هزینه', 'خسارت', 'مالی']),
    AssistantIntent('user_performance', 'عملکرد کاربران', ['عملکرد', 'کاربران', 'کارمند']),
    AssistantIntent('warranty', 'گارانتی‌ها', ['گارانتی', 'ضمانت']),
    AssistantIntent('cancelled_invoices', 'فاکتورهای ابطال‌شده', ['ابطال', 'ابطالی', 'ابطال شده']),
    AssistantIntent('daily_report', 'گزارش روزانه کامل', ['گزارش روزانه', 'گزارش کامل', 'رخداد', 'گزارش']),
    AssistantIntent('balance', 'بدهی و قابل وصول', ['بدهی', 'باقیمانده', 'قابل وصول', 'بدهکار', 'طلب']),
    AssistantIntent('backup', 'بک‌آپ', ['بک اپ', 'بک آپ', 'بکاپ', 'پشتیبان', 'بک‌آپ']),
    AssistantIntent('forecast', 'پیش‌بینی فروش', ['پیش بینی', 'پیشبینی']),
  ];

  /// پردازش پیام کاربر — موتور نیت + اجرای عملیات
  static Future<AssistantReply> handle(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) {
      return const AssistantReply('دستوری بنویسید. مثال: «پرینت فیش شماره RCP-14050904-001»');
    }
    final me = AppSession.I.currentUser;
    final norm = normalizeQuery(raw);
    _lastNorm = norm;

    // ── پیگیری گزینه‌های شفاف‌سازی — کاربر با شماره یا نام جواب داده است ──
    if (_lastOptions.isNotEmpty) {
      final picked = _pickClarification(norm);
      _lastOptions = const [];
      if (picked != null) return picked.run();
    }

    final code = _codeIn(norm);
    final range = extractDateRange(norm);

    // ── اولویت قدیمی — پرینت/چاپ فیش با شماره رسید ──
    if (code != null && RegExp(r'(پرینت|چاپ|فیش|رسید)').hasMatch(norm)) {
      return _guard(me, 'page.orders', () => _printReceipt(code));
    }

    // ── موتور نیت — امتیازدهی کلیدواژه‌ها (بند ۱۶) ──
    final scored = _scoreIntents(norm);
    if (scored.isEmpty || scored.first.$2 == 0) {
      return _helpReply();
    }
    final top = scored.first.$2;
    final tied = scored.where((e) => e.$2 == top).toList();
    if (tied.length > 1) {
      // تساوی دو نیت یا بیشتر — سوال شفاف‌سازی با گزینه‌های شماره‌دار
      return _clarifyIntents(tied.take(5).toList(), code, range, me);
    }
    return _runIntent(scored.first.$1.id, norm, code, range, me);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // لایه درک زبان — نرمال‌سازی، استخراج تاریخ، تشخیص نیت (توابع خالص برای تست)
  // ─────────────────────────────────────────────────────────────────────────

  /// نرمال‌سازی ورودی: ارقام فارسی/عربی → انگلیسی، حروف عربی → فارسی، حذف اعراب،
  /// نیم‌فاصله → فاصله، حذف علائم نگارشی و کلمات پرکننده رایج (بند ۱۶)
  static String normalizeQuery(String input) {
    var s = input;
    // ارقام عربی-هندی (٠-٩) و فارسی (۰-۹) → انگلیسی — برای تاریخ و شماره رسید
    const arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(arDigits[i], '$i');
    }
    s = toEnglishDigits(s);
    // یکسان‌سازی حروف عربی با معادل فارسی
    s = s
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ة', 'ه')
        .replaceAll('ۀ', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ٱ', 'ا');
    // حذف اعراب + نیم‌فاصله → فاصله (سفارش‌های → سفارش های)
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    s = s.replaceAll('\u200C', ' ');
    s = s.toLowerCase();
    // علائم نگارشی فارسی که در بازه \u0600-\u06FF هستند — جداگانه پاک می‌شوند
    s = s.replaceAll('؟', ' ').replaceAll('،', ' ').replaceAll('؛', ' ');
    // حذف علائم نگارشی — به‌جز / و - که تاریخ شمسی و شماره رسید به آن‌ها نیاز دارند
    s = s.replaceAll(RegExp(r'[^\w\u0600-\u06FF/\- ]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // حذف کلمات پرکننده رایج درخواست‌ها — به‌صورت توکن کامل
    const fillers = {
      'لطفا', 'میخوام', 'میخواهم', 'می', 'خوام', 'خواهم',
      'به', 'من', 'رو', 'را', 'چند', 'چطور',
    };
    final keep = <String>[];
    for (final w in s.split(' ')) {
      if (w.isEmpty || fillers.contains(w)) continue;
      keep.add(w);
    }
    return keep.join(' ');
  }

  /// استخراج بازه تاریخی از سوال — خروجی (از، تا) میلادی یا (null, null)
  /// پشتیبانی: امروز، دیروز، این هفته، هفته گذشته، این ماه، ماه گذشته،
  /// «N روز اخیر/گذشته» و تاریخ شمسی صریح ۱۴۰۵/۰۹/۰۱ یا «از ... تا ...»
  static (DateTime?, DateTime?) extractDateRange(String text) {
    final t = normalizeQuery(text);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // تاریخ شمسی صریح — یکی یا دو تاریخ (از ... تا ...)
    final dates = RegExp(r'(\d{4})\s*/\s*(\d{1,2})\s*/\s*(\d{1,2})')
        .allMatches(t)
        .map((m) => parseShamsi('${m.group(1)}/${m.group(2)}/${m.group(3)}'))
        .whereType<DateTime>()
        .toList();
    if (dates.length >= 2) {
      final a = dates[0];
      final b = dates[1];
      return a.isBefore(b) ? (a, b) : (b, a);
    }
    if (dates.length == 1) {
      final d = dates[0];
      return (d, d);
    }

    // «N روز اخیر/گذشته/پیش»
    final nDays = RegExp(r'(\d+)\s*روز').firstMatch(t);
    if (nDays != null &&
        (t.contains('اخیر') || t.contains('گذشته') || t.contains('پیش'))) {
      final n = int.tryParse(nDays.group(1)!) ?? 0;
      if (n > 0) {
        return (today.subtract(Duration(days: n - 1)), today);
      }
    }

    // بند ۱۶ — «فردا چه کارهایی را داریم؟»
    if (t.contains('فردا') && !t.contains('پس‌فردا')) {
      final tm = today.add(const Duration(days: 1));
      return (tm, tm);
    }
    if (t.contains('پس‌فردا')) {
      final tm = today.add(const Duration(days: 2));
      return (tm, tm);
    }
    if (t.contains('دیروز')) {
      final y = today.subtract(const Duration(days: 1));
      return (y, y);
    }
    // شروع هفته شنبه است — (weekday + 1) % 7 روز از شنبه فاصله دارد
    final weekStart = today.subtract(Duration(days: (today.weekday + 1) % 7));
    if (t.contains('این هفته')) return (weekStart, today);
    if (t.contains('هفته گذشته') || t.contains('هفته قبل')) {
      final lastStart = weekStart.subtract(const Duration(days: 7));
      return (lastStart, lastStart.add(const Duration(days: 6)));
    }
    final firstThisMonth = DateTime(now.year, now.month, 1);
    if (t.contains('ماه گذشته') || t.contains('ماه قبل')) {
      final firstLast = DateTime(firstThisMonth.year, firstThisMonth.month - 1, 1);
      return (firstLast, firstThisMonth.subtract(const Duration(days: 1)));
    }
    if (t.contains('این ماه')) return (firstThisMonth, today);
    if (t.contains('امروز')) return (today, today);
    return (null, null);
  }

  /// تشخیص نیت از متن — بدون نیاز به دیتابیس (بند ۱۶)
  /// خروجی: شناسه نیت؛ بدون کلیدواژه → «help»؛ تساوی → نیت مقدم‌تر در کاتالوگ.
  static String detectIntent(String text) {
    final norm = normalizeQuery(text);
    final scored = _scoreIntents(norm);
    if (scored.isEmpty || scored.first.$2 == 0) return 'help';
    return scored.first.$1.id;
  }

  /// امتیازدهی نیت‌ها — تعداد کلیدواژه‌های موجود در متن؛ تساوی با ترتیب کاتالوگ
  static List<(AssistantIntent, int)> _scoreIntents(String norm) {
    final out = <(AssistantIntent, int)>[];
    for (var i = 0; i < _intents.length; i++) {
      var score = 0;
      for (final kw in _intents[i].keywords) {
        if (norm.contains(kw)) score++;
      }
      out.add((_intents[i], score));
    }
    out.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      return _intents.indexOf(a.$1).compareTo(_intents.indexOf(b.$1));
    });
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // شفاف‌سازی ابهام (بند ۱۶) — گزینه‌های شماره‌دار + حافظه کوتاه‌مدت
  // ─────────────────────────────────────────────────────────────────────────

  static _Opt? _pickClarification(String norm) {
    // انتخاب با نام — کل یا بخشی از برچسب گزینه
    for (final o in _lastOptions) {
      if (o.label.length >= 2 &&
          (norm.contains(o.label) ||
              (norm.length >= 3 && o.label.contains(norm)))) {
        return o;
      }
    }
    // انتخاب با شماره — «شماره ۲»، «گزینه ۲» یا فقط «۲»
    final m = RegExp(r'^(?:گزینه|شماره)?\s*([1-9])$').firstMatch(norm);
    if (m != null) {
      final idx = int.tryParse(m.group(1)!) ?? 0;
      if (idx >= 1 && idx <= _lastOptions.length) return _lastOptions[idx - 1];
    }
    return null;
  }

  static Future<AssistantReply> _clarifyIntents(
      List<(AssistantIntent, int)> tied,
      String? code,
      (DateTime?, DateTime?) range,
      AuthUser? me) async {
    final opts = <_Opt>[];
    final lines = <String>[];
    for (final (intent, _) in tied) {
      final n = opts.length + 1;
      lines.add('${toPersianDigits('$n')}. ${intent.title}');
      final id = intent.id;
      final capturedNorm = _lastNorm;
      opts.add(_Opt(intent.title,
          () => _runIntent(id, capturedNorm, code, range, me)));
    }
    _lastOptions = opts;
    return AssistantReply(
      'دستورت دقیقاً کدام است؟ یکی از گزینه‌ها را با شماره یا نام انتخاب کن:\n'
      '${lines.join('\n')}',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // اجرای نیت‌ها با پالایش دسترسی (بند ۱۶)
  // ─────────────────────────────────────────────────────────────────────────

  /// پالایش دسترسی — نیت‌های مربوط به هر صفحه فقط با اجازه همان صفحه پاسخ داده
  /// می‌شوند. بدون نشست (پیش از ورود) سخت‌گیری نمی‌کنیم تا رفتار قدیمی دست نخورد.
  static Future<AssistantReply> _guard(AuthUser? me, String perm,
      Future<AssistantReply> Function() run) async {
    if (me != null && !me.can(perm)) {
      return const AssistantReply('دسترسی لازم را نداری.');
    }
    return run();
  }

  static Future<AssistantReply> _runIntent(String id, String norm,
      String? code, (DateTime?, DateTime?) range, AuthUser? me) async {
    switch (id) {
      case 'print_receipt':
        if (code == null) {
          return const AssistantReply(
              'شماره رسید را بنویسید؛ مثال: «پرینت فیش شماره RCP-14050904-001»');
        }
        return _guard(me, 'page.orders', () => _printReceipt(code));
      case 'order_status':
        return _guard(me, 'page.orders', () => _intentOrderStatus(norm, code));
      case 'orders_summary':
        return _guard(me, 'page.orders', () => _intentOrdersSummary(range, norm));
      case 'reminders':
        return _guard(me, 'page.reminders', () => _intentReminders(range));
      case 'finance':
        return _guard(me, 'page.invoices', () => _intentFinance(range));
      case 'user_performance':
        return _intentUserPerformance(me, range);
      case 'warranty':
        return _guard(me, 'page.warranty', () => _intentWarranty(code));
      case 'cancelled_invoices':
        return _guard(me, 'page.invoices', () => _intentCancelledInvoices());
      case 'daily_report':
        return _intentDailyReport(me, norm, range);
      case 'balance':
        return _guard(me, 'page.orders', () async {
          if (code != null) return _ticketBalance(code);
          return _receivablesSummary();
        });
      case 'backup':
        // عملیات نگه‌داری داده — مانند قبل بدون پالایش صفحه (سازگاری رو به عقب)
        return _intentBackup(norm);
      case 'forecast':
        return _guard(me, 'page.home', () => _forecastSummary());
      default:
        return _helpReply();
    }
  }

  // ── نیت: وضعیت سفارش با شماره رسید یا نام مشتری (بند ۱۶-الف) ──

  static Future<AssistantReply> _intentOrderStatus(String norm, String? code) async {
    if (code != null) {
      final t = await _ticketByCode(code);
      if (t != null) return _ticketStatusReply(t);
    }
    final term = _extractSearchTerm(norm);
    if (term.isEmpty) {
      return const AssistantReply(
          'شماره سفارش یا نام مشتری را بنویسید؛ مثال: «وضعیت سفارش RCP-14050904-001» یا «وضعیت سفارش آقای رضایی»');
    }
    final customers = await _searchCustomers(term);
    if (customers.isEmpty) {
      return AssistantReply(code != null
          ? 'سفارش «$code» پیدا نشد و مشتریِ مشابهی هم در برنامه نیست. شماره را از کارتابل چک کنید.'
          : 'مشتری یا سفارشی با «$term» پیدا نشد.');
    }
    if (customers.length == 1) return _customerTickets(customers.first);
    // چند مشتری مشابه — سوال شفاف‌سازی (حداکثر ۵ گزینه)
    final opts = <_Opt>[];
    final lines = <String>[];
    for (final c in customers.take(5)) {
      final n = opts.length + 1;
      lines.add('${toPersianDigits('$n')}. ${c.name}');
      opts.add(_Opt(c.name, () => _customerTickets(c)));
    }
    _lastOptions = opts;
    return AssistantReply(
      'چند مشتری با این نام پیدا شد؛ کدام را می‌خواهی؟ (با شماره یا نام جواب بده)\n'
      '${lines.join('\n')}',
    );
  }

  static Future<AssistantReply> _customerTickets(Customer c) async {
    final tickets =
        (await TicketRepo.all()).where((t) => t.customerId == c.id).toList();
    if (tickets.isEmpty) {
      return AssistantReply('برای ${c.name} سفارشی ثبت نشده است.');
    }
    final lines = [
      for (final t in tickets.take(10))
        '${t.code} — ${statusLabel(t.status)} — موعد: ${shamsiDate(t.dueDate)}',
    ];
    return AssistantReply(
      'سفارش‌های ${c.name} (${toPersianDigits('${tickets.length}')} مورد):\n'
      '${lines.join('\n')}',
      actions: [const AssistantAction('باز کردن سفارش', 'ticket')],
    );
  }

  /// استخراج عبارت جست‌وجو — حذف کلیدواژه‌های نیت و واژه‌های عمومی از متن
  static const List<String> _stopTerms = [
    'وضعیت', 'سفارش', 'پیگیری', 'مشتری', 'بدهی', 'باقیمانده', 'قابل', 'وصول',
    'کجاست', 'چی', 'شده', 'است', 'داریم', 'دارم', 'چقدر', 'چقدره', 'بگو',
    'بده', 'بدانم', 'گارانتی', 'ضمانت', 'فروش', 'درآمد', 'یادآوری', 'یاداوری',
    'موعد', 'تحویل', 'امروز', 'دیروز', 'هفته', 'ماه', 'روز', 'اخیر', 'گذشته',
    'این', 'از', 'تا', 'گزارش', 'پرینت', 'فیش', 'چاپ', 'رسید',
  ];

  static String _extractSearchTerm(String norm) {
    var t = norm;
    final code = _codeIn(norm);
    if (code != null) t = t.replaceAll(code.toLowerCase(), ' ');
    for (final w in _stopTerms) {
      t = t.replaceAll(w, ' ');
    }
    final words = t
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();
    return words.join(' ').trim();
  }

  static Future<List<Customer>> _searchCustomers(String term) async {
    final direct = await CustomerRepo.search(term);
    if (direct.isNotEmpty) return direct;
    // عبارت کامل پیدا نشد — تک‌تک واژه‌ها از بلند به کوتاه
    final words = term.split(' ').where((w) => w.length >= 2).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final w in words) {
      final r = await CustomerRepo.search(w);
      if (r.isNotEmpty) return r;
    }
    return const [];
  }

  // ── نیت: خلاصه سفارش‌های باز / امروز / این هفته / این ماه (بند ۱۶-ب) ──

  static Future<AssistantReply> _intentOrdersSummary(
      (DateTime?, DateTime?) range, String norm) async {
    final all = await TicketRepo.all();
    final nameMap = await CustomerRepo.nameMap();
    final openOnly = norm.contains('باز');
    var list = all.where((t) => t.status != 'cancelled').toList();
    if (openOnly) list = list.where((t) => t.status != 'delivered').toList();
    final (from, to) = range;
    if (from != null) {
      list = list.where((t) => !t.intakeDate.isBefore(_dayStart(from))).toList();
    }
    if (to != null) {
      list = list.where((t) => t.intakeDate.isBefore(_nextDay(to))).toList();
    }
    if (list.isEmpty) {
      return const AssistantReply('سفارشی در این بازه پیدا نشد.');
    }
    final byStatus = <String, int>{};
    for (final t in list) {
      byStatus[t.status] = (byStatus[t.status] ?? 0) + 1;
    }
    final parts = [
      for (final e in byStatus.entries)
        '${statusLabel(e.key)}: ${toPersianDigits('${e.value}')}',
    ];
    final lines = <String>[];
    for (final t in list.take(6)) {
      lines.add('${t.code} — ${nameMap[t.customerId] ?? ''} — ${statusLabel(t.status)}');
    }
    final period = from != null
        ? ' از ${shamsiDate(from)}${to != null ? ' تا ${shamsiDate(to)}' : ''}'
        : '';
    return AssistantReply(
      '${openOnly ? 'سفارش‌های باز' : 'سفارش‌ها'}$period: '
      '${toPersianDigits('${list.length}')} مورد\n'
      '${parts.join('، ')}\n'
      '${lines.join('\n')}',
    );
  }

  // ── نیت: یادآوری‌های امروز — رفع اشکال «همیشه می‌گوید هیچ» (بند ۱۶-ج) ──
  /// اشکال قبلی: dueBetween(now, now+۱روز) به‌خاطر ساعتِ «الان»، سفارش‌هایی که
  /// موعدشان ابتدای امروز بود را کنار می‌گذاشت. اکنون بازه از ابتدای روز است و
  /// یادآوری‌های در انتظار تا ۷ روز آینده هم لیست می‌شوند.

  static Future<AssistantReply> _intentReminders(
      (DateTime?, DateTime?) range) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // بند ۱۶ — بازه تک‌روزی غیرامروزی (فردا/پس‌فردا/تاریخ صریح) پذیرفته می‌شود
    final (rFrom, rTo) = range;
    var from = today;
    var dayLabel = 'امروز';
    if (rFrom != null && rTo != null && rFrom == rTo && rFrom != today) {
      from = rFrom;
      dayLabel = shamsiDate(rFrom);
    }
    final tomorrow = from.add(const Duration(days: 1));
    final dueToday = (await TicketRepo.dueBetween(from, tomorrow))
        .where((t) => t.status != 'cancelled')
        .toList();
    final pending =
        await ReminderRepo.pendingBefore(tomorrow.add(const Duration(days: 7)));
    if (dueToday.isEmpty && pending.isEmpty) {
      return AssistantReply('یادآوری برای $dayLabel نداری.');
    }
    final nameMap = await CustomerRepo.nameMap();
    final tickets = await TicketRepo.all();
    final codeById = {for (final t in tickets) t.id!: t.code};
    final lines = <String>[
      for (final t in dueToday)
        'موعد تحویل $dayLabel — ${t.code} — ${nameMap[t.customerId] ?? ''} — '
            'ساعت ${t.dueTime} — ${statusLabel(t.status)}',
      for (final r in pending)
        'یادآوری ${shamsiDate(r.remindAt)}'
            '${r.ticketId != null && codeById.containsKey(r.ticketId) ? ' — ${codeById[r.ticketId]}' : ''}'
            ': ${r.message}',
    ];
    return AssistantReply(
      '${toPersianDigits('${lines.length}')} یادآوری تا ۷ روز آینده:\n${lines.join('\n')}',
    );
  }

  // ── نیت: مالی — فروش/تخفیف/هزینه/خسارت/سود خالص یک بازه (بند ۱۶-د) ──

  static Future<AssistantReply> _intentFinance((DateTime?, DateTime?) range) async {
    final now = DateTime.now();
    var (from, to) = range;
    // بدون تاریخ صریح — این ماه
    from ??= DateTime(now.year, now.month, 1);
    to ??= now;
    final (count, gross, disc, cost, damage, profit) =
        await _financeTotals(from, to);
    final period = 'از ${shamsiDate(from)} تا ${shamsiDate(to)}';
    return AssistantReply(
      'مالی $period — ${toPersianDigits('$count')} فاکتور قطعی (غیر ابطالی):\n'
      'فروش ناخالص: ${moneyToman(gross)}\n'
      'تخفیف: ${moneyToman(disc)}\n'
      'هزینه: ${moneyToman(cost)}\n'
      'خسارت: ${moneyToman(damage)}\n'
      'سود خالص: ${moneyToman(profit)}',
    );
  }

  /// جمع مالی فاکتورهای قطعی غیر ابطالی در بازه — بر پایه netProfitOf (بند ۱۲)
  /// خروجی: (تعداد، ناخالص، تخفیف، هزینه، خسارت، سود خالص)
  static Future<(int, int, int, int, int, int)> _financeTotals(
      DateTime? from, DateTime? to) async {
    final db = await Db.instance();
    final where = <String>["kind = 'final'", "status != 'cancelled'"];
    final args = <Object?>[];
    if (from != null) {
      where.add('issued_at >= ?');
      args.add(_dayStart(from).toIso8601String());
    }
    if (to != null) {
      where.add('issued_at < ?');
      args.add(_nextDay(to).toIso8601String());
    }
    final rows = await db.query('invoices',
        where: where.join(' AND '), whereArgs: args);
    var gross = 0, disc = 0, cost = 0, damage = 0, profit = 0;
    for (final r in rows) {
      gross += (r['total'] ?? 0) as int;
      disc += (r['discount'] ?? 0) as int;
      cost += (r['cost'] ?? 0) as int;
      damage += (r['damage'] ?? 0) as int;
      profit += InvoiceRepo.netProfitOf(r);
    }
    return (rows.length, gross, disc, cost, damage, profit);
  }

  // ── نیت: عملکرد کاربران در بازه — با کنترل دسترسی (بند ۱۶-ه) ──

  static Future<AssistantReply> _intentUserPerformance(
      AuthUser? me, (DateTime?, DateTime?) range) async {
    // فقط مدیر/سازنده یا دارنده دسترسی صفحه KPI — وگرنه پاسخ مودبانهِ انصراف
    if (me != null &&
        !(me.isAdmin || me.isCreator || me.perms.contains('page.kpi'))) {
      return const AssistantReply(
          'دسترسی لازم را نداری — گزارش عملکرد کاربران فقط برای مدیر سیستم است.');
    }
    final now = DateTime.now();
    var (from, to) = range;
    from ??= now.subtract(const Duration(days: 30));
    to ??= now;
    final kpis = await HomeStatsService.employeeKpis(from, to);
    if (kpis.isEmpty) {
      return const AssistantReply('در این بازه فعالیتی از کاربران ثبت نشده است.');
    }
    final lines = [
      for (final k in kpis.take(10))
        '${k.name}: ${toPersianDigits('${k.created}')} ثبت‌شده، '
            '${toPersianDigits('${k.delivered}')} تحویل، '
            '${toPersianDigits(k.share.toStringAsFixed(0))}٪ سهم',
    ];
    return AssistantReply(
      'عملکرد کاربران از ${shamsiDate(from)} تا ${shamsiDate(to)}:\n${lines.join('\n')}',
    );
  }

  // ── نیت: گارانتی‌های در هشدار/منقضی (بند ۱۶-و) ──

  static Future<AssistantReply> _intentWarranty(String? code) async {
    if (code != null) return _warrantyInfo(code);
    final alerts = await ForecastService.warrantyAlertDetails();
    if (alerts.isEmpty) {
      return const AssistantReply('گارانتی ثبت‌شده‌ای وجود ندارد.');
    }
    final expiring = alerts.where((a) => a.expiring).toList();
    final expired = alerts.where((a) => a.expired).toList();
    final lines = <String>[
      'گارانتی‌ها: ${toPersianDigits('${alerts.length - expiring.length - expired.length}')} فعال، '
          '${toPersianDigits('${expiring.length}')} در هشدار (۳۰ روز پایانی)، '
          '${toPersianDigits('${expired.length}')} منقضی.',
    ];
    for (final a in [...expiring.take(3), ...expired.take(2)]) {
      lines.add('${a.ticketCode} — ${a.itemName} — تا ${shamsiDate(a.endDate)} '
          '${a.expired ? '(منقضی)' : '(در هشدار)'}');
    }
    return AssistantReply(lines.join('\n'));
  }

  // ── نیت: فاکتورهای ابطال‌شده — تعداد و جمع به تفکیک نوع (بند ۱۶-ز) ──

  static Future<AssistantReply> _intentCancelledInvoices() async {
    final db = await Db.instance();
    final rows =
        await db.query('invoices', where: "status = 'cancelled'");
    if (rows.isEmpty) {
      return const AssistantReply('هیچ سند ابطالی ثبت نشده است.');
    }
    var preCount = 0, preSum = 0, finCount = 0, finSum = 0;
    for (final r in rows) {
      final kind = (r['kind'] ?? '') as String;
      final total = (r['total'] ?? 0) as int;
      if (kind == InvoiceRepo.kindPre) {
        preCount++;
        preSum += total;
      } else if (kind == InvoiceRepo.kindFinal) {
        finCount++;
        finSum += total;
      }
    }
    final lines = <String>[
      'پیش‌فاکتور: ${toPersianDigits('$preCount')} سند — جمع ${moneyToman(preSum)}',
      'فاکتور قطعی: ${toPersianDigits('$finCount')} سند — جمع ${moneyToman(finSum)}',
    ];
    // آخرین ابطالی‌ها — رفتار قدیمی حفظ شده
    final recent = await db.query('invoices',
        where: "status = 'cancelled'", orderBy: 'id DESC', limit: 5);
    for (final r in recent) {
      final reason = ((r['cancel_reason'] ?? '') as String);
      lines.add('${toPersianDigits((r['number'] ?? '') as String)} — '
          '${moneyToman((r['total'] ?? 0) as int)}'
          '${reason.isEmpty ? '' : ' — دلیل: $reason'}');
    }
    return AssistantReply(
      'سند ابطال‌شده‌ها (ابطال به‌جای حذف — بند ۱۳):\n${lines.join('\n')}\n'
      '(لیست کامل: صفحه «فاکتورها → ابطال‌شده‌ها»)',
    );
  }

  // ── نیت: گزارش کامل روزانه — ترکیب یادآوری + مالی + گارانتی (بند ۱۶-ح) ──

  static Future<AssistantReply> _intentDailyReport(
      AuthUser? me, String norm, (DateTime?, DateTime?) range) async {
    // «گزارش دیروز» — رفتار قدیمی گزارش رخدادها حفظ شده
    if (norm.contains('دیروز')) return _dailyReportSummary(true);
    final now = DateTime.now();
    var (from, to) = range;
    from ??= DateTime(now.year, now.month, now.day);
    to ??= from;
    final lines = <String>[];
    // بخش یادآوری‌ها
    if (me == null || me.can('page.reminders')) {
      final today = DateTime(now.year, now.month, now.day);
      final dueToday = (await TicketRepo.dueBetween(
              today, today.add(const Duration(days: 1))))
          .where((t) => t.status != 'cancelled')
          .length;
      final pending = (await ReminderRepo.pendingBefore(
              today.add(const Duration(days: 8))))
          .length;
      lines.add('یادآوری‌ها: ${toPersianDigits('$dueToday')} سفارش موعد امروز، '
          '${toPersianDigits('$pending')} یادآوری در انتظار');
    }
    // بخش مالی
    if (me == null || me.can('page.invoices')) {
      final (count, gross, disc, cost, damage, profit) =
          await _financeTotals(from, to);
      lines.add('مالی: ${toPersianDigits('$count')} فاکتور قطعی — '
          'فروش ناخالص ${moneyToman(gross)} — سود خالص ${moneyToman(profit)} '
          '(تخفیف ${moneyToman(disc)}، هزینه ${moneyToman(cost)}، خسارت ${moneyToman(damage)})');
    }
    // بخش گارانتی
    if (me == null || me.can('page.warranty')) {
      final alerts = await ForecastService.warrantyAlertDetails();
      final expiring = alerts.where((a) => a.expiring).length;
      final expired = alerts.where((a) => a.expired).length;
      lines.add('گارانتی: ${toPersianDigits('$expiring')} در هشدار، '
          '${toPersianDigits('$expired')} منقضی');
    }
    if (lines.isEmpty) {
      return const AssistantReply('دسترسی لازم را نداری.');
    }
    final events = await DailyReportService.eventsOf(from);
    return AssistantReply(
      'گزارش کامل از ${shamsiDate(from)} تا ${shamsiDate(to)}:\n'
      '${lines.join('\n')}\n'
      'رخدادهای ثبت‌شده: ${toPersianDigits('${events.length}')} مورد',
    );
  }

  // ── نیت: بک‌آپ — رفتار قدیمی ──

  static Future<AssistantReply> _intentBackup(String norm) async {
    if (norm.contains('بگیر') || norm.contains('بساز') || norm.contains('انجام')) {
      final path = await BackupService.manualBackup();
      return AssistantReply('بک‌آپ کامل گرفته شد و ذخیره شد:\n$path');
    }
    final autos = await BackupService.listAuto();
    final manuals = await BackupService.listManual();
    return AssistantReply(
      'بک‌آپ‌ها: ${toPersianDigits('${manuals.length}')} بک‌آپ دستی و '
      '${toPersianDigits('${autos.length}')} بک‌آپ اتوماتیک موجود است. '
      'بک‌آپ‌های اتوماتیک بعد از ۳۰ روز خودکار پاک می‌شوند. برای بازیابی به ماژول «مدیریت دیتابیس» بروید.',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // اجراکننده‌های قدیمی — حفظ‌شده برای سازگاری رو به عقب
  // ─────────────────────────────────────────────────────────────────────────

  static String? _codeIn(String text) {
    final m = RegExp(r'rcp-\d+-\d+').firstMatch(text);
    if (m != null) return m.group(0)!.toUpperCase();
    return null;
  }

  static Future<Ticket?> _ticketByCode(String code) async {
    final wanted = code.toUpperCase();
    for (final t in await TicketRepo.all()) {
      if (t.code.toUpperCase() == wanted) return t;
    }
    return null;
  }

  static Future<AssistantReply> _printReceipt(String code) async {
    final ticket = await _ticketByCode(code);
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

  static Future<AssistantReply> _ticketStatusReply(Ticket ticket) async {
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
    final ticket = await _ticketByCode(code);
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

  static Future<AssistantReply> _warrantyInfo(String code) async {
    final ticket = await _ticketByCode(code);
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

  static Future<AssistantReply> _forecastSummary() async {
    final future = await ForecastService.forecast(months: 3);
    final total = future.fold<double>(0, (s, e) => s + e.value);
    return AssistantReply(
      'پیش‌بینی صادقانه (میانگین متحرک ۳ ماه گذشته): '
      'درآمد تقریبی هر یک از ۳ ماه آینده حدود ${moneyToman(total ~/ 3)} تومان است. '
      'نمودار خطی داشبورد همین پیش‌بینی را با خط‌چین نشان می‌دهد.',
    );
  }

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

  // ── ابزارهای بازه روز ──

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// ابتدای روز بعد — برای شرط انتهای بازه (شامل خود روز «تا»)
  static DateTime _nextDay(DateTime d) =>
      _dayStart(d).add(const Duration(days: 1));

  static AssistantReply _helpReply() {
    return const AssistantReply(
      'کارهایی که می‌توانم انجام بدهم:\n'
      '• «پرینت فیش شماره RCP-14050904-001» — ساخت PDF رسید و باز شدن برای چاپ\n'
      '• «وضعیت سفارش RCP-14050904-001» یا «وضعیت سفارش آقای رضایی»\n'
      '• «خلاصه سفارش‌های باز» / «سفارش‌های امروز»\n'
      '• «یادآوری‌های امروز»\n'
      '• «فروش این ماه» / «سود خالص از ۱۴۰۵/۰۸/۰۱ تا ۱۴۰۵/۰۹/۰۱»\n'
      '• «گزارش کامل امروز» — یادآوری + مالی + گارانتی\n'
      '• «عملکرد کاربران» (فقط مدیر)\n'
      '• «گارانتی‌های در هشدار» / «فاکتورهای ابطال‌شده»\n'
      '• «بدهی RCP-14050904-001» یا «چقدر قابل وصول داریم؟»\n'
      '• «بک‌آپ بگیر» — پشتیبان کامل و بی‌درنگ\n'
      'همه پاسخ‌ها از دیتابیس محلی خود برنامه ساخته می‌شود؛ بدون نیاز به اینترنت.',
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
