/// سرویس همگام‌سازی Google Sheet — جایگزین کانال Google Calendar
///
/// کانال جدید: شیت «داشبورد تعمیرات و خدمات J.S.H» که برنامه مدیریت می‌کند و
/// با شرکت و توسعه‌دهنده به اشتراک گذاشته شده است.
///
/// معماری آفلاین‌محور:
///  • مرجع داده = SQLite محلی؛ هر سفارش قبل از ارسال در جدول sheet_outbox صف می‌شود.
///  • ارسال از طریق Apps Script Web App (آدرس در settings ذخیره می‌شود) انجام
///    می‌شود؛ بدون کلید API داخل برنامه — ایمن روی ویندوز و اندروید.
///  • بدون اینترنت یا بدون آدرس endpoint → «در صف آفلاین» می‌ماند؛ هیچ داده‌ای
///    گم نمی‌شود و با اولین اتصال flush می‌شود.
///  • قاعده ۱: ارقام فارسی برای نمایش (تاریخ شمسی، هزینه)؛ شناسه و میلادی انگلیسی.
///  • شماره تلفن با پیشوند آپاستروف متنی می‌ماند تا صفر ابتدایی حذف نشود.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants.dart';
import '../db/db.dart';
import '../utils.dart';

/// ستون‌های شیت — هماهنگ با ماژول پایتونی src/jsh/sheets_sync.py
class SheetSyncConst {
  static const String sheetId = '1UqbXVRUE0Fyf_CWS8Crr6mCGsEmSpvulLzt-IRoK6IQ';
  static const String sheetUrl =
      'https://docs.google.com/spreadsheets/d/$sheetId/edit';
  static const String defaultTab = 'داشبورد تعمیرات و خدمات J.S.H';
  static const List<String> headers = [
    'ردیف', 'شناسه سفارش', 'نام مشتری', 'تلفن', 'دستگاه',
    'شرح خرابی', 'تاریخ شمسی', 'تاریخ میلادی', 'وضعیت',
    'هزینه (تومان)', 'یادداشت', 'زمان ثبت',
  ];
  static const String endpointSettingKey = 'sheet_sync_endpoint';
  static const String outboxTable = '''
    CREATE TABLE IF NOT EXISTS sheet_outbox (
      code TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      synced INTEGER DEFAULT 0,
      retries INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    )''';
}

/// گزارش همگام‌سازی برای نمایش در رابط کاربری
class SheetSyncReport {
  final int queued;
  final int sent;
  final bool online;

  const SheetSyncReport({
    required this.queued,
    required this.sent,
    required this.online,
  });

  String get fa {
    final parts = <String>[];
    if (sent > 0) parts.add('$sent ردیف به شیت ارسال شد');
    if (queued > 0) {
      parts.add(online
          ? '$queued ردیف در صف آفلاین ماند (ارسال ناموفق)'
          : 'بدون اینترنت — $queued ردیف در صف آفلاین ماند');
    }
    if (parts.isEmpty) return 'همه سفارش‌ها همگام هستند';
    return parts.join('؛ ');
  }
}

class SheetSyncService {
  /// جدول صف آفلاین را (در صورت نبود) می‌سازد — بدون تغییر نسخه بانک
  static Future<void> _ensureOutbox(Database db) async {
    await db.execute(SheetSyncConst.outboxTable);
  }

  /// آدرس Apps Script Web App از settings؛ خالی = فقط صف آفلاین
  static Future<String?> endpoint() async {
    final db = await Db.instance();
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [SheetSyncConst.endpointSettingKey]);
    final v = rows.isEmpty ? null : rows.first['value'] as String?;
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  static Future<void> setEndpoint(String url) async {
    final db = await Db.instance();
    await db.insert('settings',
        {SheetSyncConst.endpointSettingKey: url.trim()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// تاریخ شمسی با ارقام فارسی — قاعده ۱
  static String jalaliFa(DateTime d) => shamsiDate(d);

  /// یک ردیف شیت از روی داده سفارش — خالص و قابل تست
  static List<dynamic> buildRow(Map<String, dynamic> t, int rowNo,
      {DateTime? tomorrow}) {
    final due = DateTime.tryParse(t['due_date'] as String? ?? '') ??
        DateTime.now();
    final isTomorrow = tomorrow != null &&
        due.year == tomorrow.year &&
        due.month == tomorrow.month &&
        due.day == tomorrow.day;
    final note = <String>[
      if (isTomorrow) 'برگه فردا',
      if ((t['deposit_amount'] as int? ?? 0) > 0)
        'بیعانه: ${money(t['deposit_amount'] as int)} تومان',
    ].join(' - ');
    final phone = t['phone'] as String? ?? '';
    return [
      rowNo,
      t['code'], // شناسه انگلیسی برای مرتب‌سازی
      t['customer_name'] ?? '',
      // قاعده متنی ماندن تلفن — صفر ابتدایی محفوظ
      phone.startsWith('0') ? "'$phone" : phone,
      t['device_model'] ?? '',
      t['defect'] ?? '',
      jalaliFa(due),
      '${due.year.toString().padLeft(4, '0')}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
      TicketStatus.labels[t['status']] ?? t['status'],
      (t['estimate_amount'] as int? ?? 0) == 0
          ? ''
          : money(t['estimate_amount'] as int),
      note,
      t['created_at'] ?? '',
    ];
  }

  /// صف‌کردن سفارش‌ها و تلاش ارسال — هسته کانال Google Sheet
  static Future<SheetSyncReport> pushAll({bool includeDelivered = false}) async {
    final db = await Db.instance();
    await _ensureOutbox(db);

    final tickets = await db.rawQuery('''
      SELECT t.code, t.defect, t.status, t.estimate_amount,
             t.deposit_amount, t.due_date, t.created_at,
             c.name AS customer_name, c.phone AS phone,
             d.model AS device_model
      FROM tickets t
      JOIN customers c ON c.id = t.customer_id
      JOIN devices d ON d.id = t.device_id
      ${includeDelivered ? '' : "WHERE t.status != 'delivered'"}
      ORDER BY t.id ASC
    ''');

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    // جلوگیری از ارسال تکراری: کدهایی که قبلاً به شیت رسیده‌اند دیگر صف نمی‌شوند
    final syncedRows = await db.query('sheet_outbox',
        columns: ['code'], where: 'synced = 1');
    final syncedCodes = syncedRows.map((r) => r['code'] as String).toSet();
    var queued = 0;
    for (final t in tickets) {
      final code = t['code'] as String;
      if (syncedCodes.contains(code)) continue; // قبلاً در شیت هست
      await db.insert(
        'sheet_outbox',
        {
          'code': code,
          'payload': jsonEncode(buildRow(Map<String, dynamic>.from(t),
              0, tomorrow: tomorrow)),
          'synced': 0,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace, // فقط ردیف‌های در انتظار به‌روز می‌شوند
      );
      queued++;
    }

    return flush();
  }

  /// flush صف: ارسال همه ردیف‌های همگام‌نشده به Apps Script endpoint
  static Future<SheetSyncReport> flush() async {
    final db = await Db.instance();
    await _ensureOutbox(db);
    final pending = await db.query('sheet_outbox',
        where: 'synced = 0', orderBy: 'created_at ASC');
    if (pending.isEmpty) {
      return const SheetSyncReport(queued: 0, sent: 0, online: true);
    }

    final url = await endpoint();
    if (url == null) {
      return SheetSyncReport(
          queued: pending.length, sent: 0, online: false);
    }

    final rows = <List<dynamic>>[];
    final codes = <String>[];
    for (final r in pending) {
      rows.add(List<dynamic>.from(jsonDecode(r['payload'] as String) as List));
      codes.add(r['code'] as String);
    }
    // شماره ردیف را بر اساس طول ردیف‌ها بازنویسی می‌کنیم (۱..n)
    for (var i = 0; i < rows.length; i++) {
      rows[i][0] = i + 1;
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType =
          ContentType('text', 'plain', charset: 'utf-8'); // جلوگیری از preflight
      req.write(jsonEncode({
        'tab': SheetSyncConst.defaultTab,
        'sheetId': SheetSyncConst.sheetId,
        'rows': rows,
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();

      if (res.statusCode == 200 && body.contains('"ok"')) {
        for (final code in codes) {
          await db.update('sheet_outbox', {'synced': 1},
              where: 'code = ?', whereArgs: [code]);
        }
        return SheetSyncReport(queued: 0, sent: codes.length, online: true);
      }
      return SheetSyncReport(
          queued: pending.length, sent: 0, online: false);
    } catch (_) {
      return SheetSyncReport(
          queued: pending.length, sent: 0, online: false);
    }
  }

  /// تعداد ردیف‌های منتظر در صف — برای نمایش وضعیت در داشبورد
  static Future<int> pendingCount() async {
    final db = await Db.instance();
    await _ensureOutbox(db);
    final rows = await db.query('sheet_outbox', where: 'synced = 0');
    return rows.length;
  }
}
