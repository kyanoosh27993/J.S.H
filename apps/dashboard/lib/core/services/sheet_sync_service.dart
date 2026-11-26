/// سرویس همگام‌سازی Google Sheet — کانال دوسویه مبتنی بر رویداد
///
/// شیت «داشبورد تعمیرات و خدمات J.S.H» آینه‌ی سفارش‌های برنامه است:
///  • افزودن سفارش در برنامه  → ردیف به شیت اضافه می‌شود (append)
///  • ویرایش سفارش در برنامه   → ردیف متناظر (با کلید «شناسه سفارش») به‌روز می‌شود (update)
///  • حذف سفارش در برنامه      → ردیف از شیت حذف می‌شود (delete)
///
/// معماری آفلاین‌محور:
///  • مرجع داده = SQLite محلی؛ هر رویداد در جدول sheet_outbox با نوع عملیات صف می‌شود.
///  • ادغام رویدادها (coalescing): اگر سفارشی چند بار ویرایش شود قبل از ارسال،
///    فقط آخرین وضعیت ارسال می‌شود؛ «حذف» روی «افزودنِ در انتظار» = حذف خود ردیف صف.
///  • ارسال از طریق Apps Script Web App (آدرس در settings)؛ بدون کلید API در برنامه.
///  • بدون اینترنت یا endpoint → در صف می‌ماند و با اولین اتصال flush می‌شود.
///  • pushAll یک «آشتی‌سازی» کامل هم انجام می‌دهد: ردیف‌های همگام‌شده‌ای که
///    داده‌شان با بانک فرق کرده (مثلاً بعد از ادغام بسته همگام‌سازی) به‌روز می‌شوند.
///  • قاعده ۱: ارقام فارسی برای نمایش (تاریخ شمسی، هزینه)؛ شناسه و میلادی انگلیسی.
///  • شماره تلفن با پیشوند آپاستروف متنی می‌ماند تا صفر ابتدایی حذف نشود.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants.dart';
import '../db/db.dart';
import '../utils.dart';

/// ستون‌های شیت — هماهنگ با Apps Script و ماژول مرجع پایتونی
class SheetSyncConst {
  static const String sheetId = '1UqbXVRUE0Fyf_CWS8Crr6mCGsEmSpvulLzt-IRoK6IQ';
  static const String sheetUrl =
      'https://docs.google.com/spreadsheets/d/$sheetId/edit';
  static const String defaultTab = 'داشبورد تعمیرات و خدمات J.S.H';
  /// ستون کلید در شیت: «شناسه سفارش» (B) — مبنای update/delete
  static const int codeColumn = 1;
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

/// نوع عملیات صف — متناظر با doPost در Apps Script
class SheetOp {
  static const String append = 'append';
  static const String update = 'update';
  static const String delete = 'delete';
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
    if (sent > 0) parts.add('$sent عملیات به شیت اعمال شد');
    if (queued > 0) {
      parts.add(online
          ? '$queued عملیات در صف آفلاین ماند (ارسال ناموفق)'
          : 'بدون اینترنت — $queued عملیات در صف آفلاین ماند');
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

  static DateTime _tomorrow() =>
      DateTime.now().add(const Duration(days: 1));

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

  // ---------------------------------------------------------------
  // رمزگذاری payload: {"op": ..., "row": [...]} — سازگار با آرایه قدیمی
  // ---------------------------------------------------------------

  static String encodePayload(String op, List<dynamic> row) =>
      jsonEncode({'op': op, 'row': row});

  /// خواندن payload — payloadهای آرایه‌ای نسخه قبلی = append در نظر گرفته می‌شوند
  static (String, List<dynamic>) decodePayload(String raw) {
    final v = jsonDecode(raw);
    if (v is List) return (SheetOp.append, List<dynamic>.from(v));
    final m = v as Map<String, dynamic>;
    return (m['op'] as String, List<dynamic>.from(m['row'] as List));
  }

  static Future<void> _enqueue(
      Database db, String code, String op, List<dynamic> row) async {
    await db.insert(
      'sheet_outbox',
      {
        'code': code,
        'payload': encodePayload(op, row),
        'synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// داده کامل یک سفارش با همان SELECT موجود در pushAll
  static Future<Map<String, dynamic>?> _ticketByCode(
      Database db, String code) async {
    final rows = await db.rawQuery('''
      SELECT t.code, t.defect, t.status, t.estimate_amount,
             t.deposit_amount, t.due_date, t.created_at,
             c.name AS customer_name, c.phone AS phone,
             d.model AS device_model
      FROM tickets t
      JOIN customers c ON c.id = t.customer_id
      JOIN devices d ON d.id = t.device_id
      WHERE t.code = ?
    ''', [code]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  // ---------------------------------------------------------------
  // هوک‌های رویداد — از TicketRepo.insert/update/delete صدا زده می‌شوند
  // ---------------------------------------------------------------

  /// پس از افزودن یا ویرایش سفارش — ردیف شیت همگام می‌شود
  static Future<void> onTicketChanged(String code) async {
    try {
      final db = await Db.instance();
      await _ensureOutbox(db);
      final t = await _ticketByCode(db, code);
      if (t == null) return; // سفارش وجود ندارد؛ حذف با onTicketDeleted
      final row = buildRow(t, 0, tomorrow: _tomorrow());
      final existing = await db
          .query('sheet_outbox', where: 'code = ?', whereArgs: [code]);
      if (existing.isEmpty) {
        await _enqueue(db, code, SheetOp.append, row);
        return;
      }
      final (op, _) =
          decodePayload(existing.first['payload'] as String);
      final synced = existing.first['synced'] as int? ?? 0;
      if (op == SheetOp.delete) {
        // حذف در صف بوده و سفارش دوباره ساخته شده → به‌روزرسانی
        await _enqueue(db, code, SheetOp.update, row);
      } else if (synced == 1) {
        // قبلاً در شیت هست → ویرایش
        await _enqueue(db, code, SheetOp.update, row);
      } else {
        // append/update در انتظار → فقط با داده تازه جایگزین می‌شود
        await _enqueue(db, code, op, row);
      }
    } catch (_) {
      // همگام‌سازی هرگز جریان اصلی برنامه را نمی‌شکند؛ دفعه بعد flush جبران می‌کند
    }
  }

  /// پس از حذف سفارش — ردیف شیت حذف می‌شود
  static Future<void> onTicketDeleted(String code) async {
    try {
      final db = await Db.instance();
      await _ensureOutbox(db);
      final existing = await db
          .query('sheet_outbox', where: 'code = ?', whereArgs: [code]);
      if (existing.isEmpty) return; // هرگز به شیت نرسیده — چیزی برای حذف نیست
      final (op, _) =
          decodePayload(existing.first['payload'] as String);
      final synced = existing.first['synced'] as int? ?? 0;
      if (op == SheetOp.append && synced == 0) {
        // فقط در صف بود و هنوز به شیت نرسیده → خود ردیف صف حذف می‌شود
        await db
            .delete('sheet_outbox', where: 'code = ?', whereArgs: [code]);
        return;
      }
      // در شیت هست (یا update در صف است) → حذف واقعی از شیت صف می‌شود
      await _enqueue(db, code, SheetOp.delete, [0, code]);
    } catch (_) {
      // همان سیاست فوق — هیچ‌گاه جریان اصلی را نمی‌شکند
    }
  }

  // ---------------------------------------------------------------
  // آشتی‌سازی کامل + flush
  // ---------------------------------------------------------------

  /// صف‌کردن سفارش‌ها و تلاش ارسال — هسته کانال Google Sheet
  ///
  /// علاوه بر سفارش‌های تازه، اختلاف ردیف‌های همگام‌شده با بانک را هم
  /// پیدا و به‌روز می‌کند (آشتی‌سازی — مثلاً بعد از ادغام بسته همگام‌سازی).
  static Future<SheetSyncReport> pushAll(
      {bool includeDelivered = false}) async {
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

    final tomorrow = _tomorrow();
    final outboxRows = await db.query('sheet_outbox');
    final outbox = <String, (String, int, List<dynamic>)>{};
    for (final r in outboxRows) {
      final (op, row) = decodePayload(r['payload'] as String);
      outbox[r['code'] as String] =
          (op, r['synced'] as int? ?? 0, row);
    }

    for (final raw in tickets) {
      final t = Map<String, dynamic>.from(raw);
      final code = t['code'] as String;
      final row = buildRow(t, 0, tomorrow: tomorrow);
      final state = outbox[code];
      if (state == null) {
        await _enqueue(db, code, SheetOp.append, row);
      } else {
        final (op, synced, oldRow) = state;
        if (synced == 1) {
          // آشتی‌سازی: اگر داده بانک با شیت فرق کرده → ویرایش
          if (!_rowsEqualExceptRowNo(oldRow, row)) {
            await _enqueue(db, code, SheetOp.update, row);
          }
        } else if (op == SheetOp.delete) {
          // حذف در صف است؛ سفارش موجود → به‌روزرسانی
          await _enqueue(db, code, SheetOp.update, row);
        } else {
          // append/update در انتظار → داده تازه می‌شود (بدون عملیات تکراری)
          await _enqueue(db, code, op, row);
        }
      }
    }

    return flush();
  }

  /// مقایسه محتوای ردیف بدون ستون «ردیف» (اندیس ۰ نمایشی است)
  static bool _rowsEqualExceptRowNo(
      List<dynamic> a, List<dynamic> b) {
    for (var i = 1; i < SheetSyncConst.headers.length; i++) {
      final av = i < a.length ? a[i] : '';
      final bv = i < b.length ? b[i] : '';
      if (av?.toString() != bv?.toString()) return false;
    }
    return true;
  }

  /// flush صف: اعمال همه عملیات در انتظار روی شیت از طریق Apps Script
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

    // هر عملیات مستقل اعمال می‌شود؛ appendها با هم در یک دسته می‌روند
    final ops = <Map<String, dynamic>>[];
    final codes = <String>[];
    for (final r in pending) {
      final (op, row) = decodePayload(r['payload'] as String);
      final code = r['code'] as String;
      ops.add({'op': op, 'code': code, 'row': row});
      codes.add(code);
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
        'headers': SheetSyncConst.headers,
        'ops': ops,
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();

      if (res.statusCode == 200 && body.contains('"ok":true')) {
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

  /// تعداد عملیات منتظر در صف — برای نمایش وضعیت در داشبورد
  static Future<int> pendingCount() async {
    final db = await Db.instance();
    await _ensureOutbox(db);
    final rows = await db.query('sheet_outbox', where: 'synced = 0');
    return rows.length;
  }
}
