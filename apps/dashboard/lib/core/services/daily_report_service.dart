/// گزارش روزانه — فاز ۶ (بند ۱۷)
/// همه تغییرات یک روز: پذیرش، تغییر وضعیت کارتابل، تحویل، وصول، تخفیف،
/// ابطال، حذف — به‌صورت لیست قابل نمایش + خروجی فایل متنی در مسیر دلخواه
/// کاربر + امکان حذف یادآوری از داخل برنامه.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/db.dart';
import '../utils.dart';

class DailyReportEntry {
  final String time;
  final String category; // پذیرش/کارتابل/تحویل/وصول/تخفیف/ابطال/حذف/سایر
  final String text;
  const DailyReportEntry(this.time, this.category, this.text);
}

class DailyReportService {
  /// رخدادهای یک روز (از نیمه‌شب تا ۲۳:۵۹) — بر پایه داده واقعی بانک
  static Future<List<DailyReportEntry>> eventsOf(DateTime day) async {
    final from = DateTime(day.year, day.month, day.day).toIso8601String();
    final to =
        DateTime(day.year, day.month, day.day + 1).toIso8601String();
    final db = await Db.instance();
    final out = <DailyReportEntry>[];

    String hh(String iso) {
      final d = DateTime.tryParse(iso);
      return d == null ? '' : toPersianDigits(
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}');
    }

    // پذیرش‌های ثبت‌شده
    final tickets = await db.query('tickets',
        where: 'created_at >= ? AND created_at < ?', whereArgs: [from, to]);
    for (final t in tickets) {
      out.add(DailyReportEntry(hh((t['created_at'] ?? '') as String), 'پذیرش',
          'ثبت سفارش ${(t['code'] ?? '') as String}'));
    }

    // تغییر وضعیت کارتابل (شامل تحویل)
    final logs = await db.query('ticket_status_log',
        where: 'created_at >= ? AND created_at < ?', whereArgs: [from, to]);
    for (final l in logs) {
      final fromS = (l['from_status'] ?? '') as String;
      final toS = (l['to_status'] ?? (l['status'] ?? '')) as String;
      final ticketId = (l['ticket_id'] ?? 0) as int;
      final reason = ((l['reason'] ?? '') as String).trim();
      out.add(DailyReportEntry(
          hh((l['created_at'] ?? '') as String),
          toS == 'delivered' ? 'تحویل' : 'کارتابل',
          'سفارش #$ticketId: ${statusLabel(fromS)} ← ${statusLabel(toS)}'
          '${reason.isEmpty ? '' : ' — دلیل: $reason'}'));
    }

    // وصول‌ها
    final payments = await db.query('payments',
        where: 'created_at >= ? AND created_at < ?', whereArgs: [from, to]);
    for (final p in payments) {
      out.add(DailyReportEntry(
          hh((p['created_at'] ?? '') as String),
          'وصول',
          'دریافت ${moneyFa((p['amount'] ?? 0) as int)} تومان برای سفارش #${(p['ticket_id'] ?? 0) as int}'));
    }

    // ابطال‌ها و تخفیف‌ها — از audit_log
    final audits = await db.query('audit_log',
        where: 'created_at >= ? AND created_at < ?', whereArgs: [from, to]);
    for (final a in audits) {
      final action = (a['action'] ?? '') as String;
      final detail = (a['detail'] ?? '') as String;
      if (action == 'invoice_cancel') {
        out.add(DailyReportEntry(hh((a['created_at'] ?? '') as String), 'ابطال', detail));
      } else if (action == 'invoice_delete') {
        out.add(DailyReportEntry(hh((a['created_at'] ?? '') as String), 'حذف', detail));
      } else if (action == 'invoice_discount') {
        out.add(DailyReportEntry(hh((a['created_at'] ?? '') as String), 'تخفیف', detail));
      } else if (action == 'invoice_create') {
        out.add(DailyReportEntry(hh((a['created_at'] ?? '') as String), 'سند', detail));
      } else if (action == 'settle') {
        out.add(DailyReportEntry(hh((a['created_at'] ?? '') as String), 'وصول', detail));
      }
    }

    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static String moneyFa(int v) =>
      toPersianDigits(v.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ','));

  /// متن گزارش برای فایل خروجی — بند ۱۷
  static String buildText(
      DateTime day, List<DailyReportEntry> entries) {
    final jdt = j.Jalali.fromDateTime(day);
    final jd = _Jd(jdt.year, jdt.month, jdt.day);
    final buf = StringBuffer();
    buf.writeln('گزارش روزانه برنامه J.S.H — ${jd.text}');
    buf.writeln('=' * 60);
    if (entries.isEmpty) {
      buf.writeln('رخدادی برای این روز ثبت نشده است.');
    }
    for (final e in entries) {
      buf.writeln('${e.time}  [${e.category}]  ${e.text}');
    }
    buf.writeln('=' * 60);
    buf.writeln('تعداد رخدادها: ${toPersianDigits('${entries.length}')}');
    return buf.toString();
  }

  /// ذخیره خروجی در مسیر دلخواه کاربر (بند ۱۷) — با file_selector
  static Future<String?> exportToUserPath(
      DateTime day, List<DailyReportEntry> entries) async {
    final jdt = j.Jalali.fromDateTime(day);
    final text = buildText(day, entries);
    final suggestedName =
        'jsh-daily-${jdt.year}${jdt.month.toString().padLeft(2, '0')}${jdt.day.toString().padLeft(2, '0')}.txt';
    String? path;
    try {
      final save = await getSaveLocation(
          suggestedName: suggestedName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'متن', extensions: ['txt'])
          ]);
      path = save?.path;
    } catch (_) {
      // ویندوز/اندروید بدون دیالوگ — مسیر پیش‌فرض اسناد
      final docs = await getApplicationDocumentsDirectory();
      final dir = p.join(docs.path, 'daily_reports');
      await Directory(dir).create(recursive: true);
      path = p.join(dir, suggestedName);
    }
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    await f.writeAsString(text, encoding: utf8);
    return path;
  }
}

/// نگه‌دارنده تاریخ شمسی برای نام فایل و سربرگ — از بسته shamsi_date
class _Jd {
  final int year;
  final int month;
  final int day;
  const _Jd(this.year, this.month, this.day);

  String get text => toPersianDigits(
      '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}');
}
