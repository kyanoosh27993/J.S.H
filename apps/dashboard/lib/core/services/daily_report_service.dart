/// گزارش روزانه — فاز ۶ (بند ۱۷) + فاز ۹ (بند ۲۷)
/// همه تغییرات یک روز: پذیرش، تغییر وضعیت کارتابل، تحویل، وصول، تخفیف،
/// ابطال، حذف — به‌صورت لیست قابل نمایش + خروجی فایل متنی در مسیر دلخواه
/// کاربر + امکان حذف یادآوری از داخل برنامه.
/// فاز ۹ — بند ۲۷: خروجی روزانه هم‌زمان txt و xlsx (اکسل بدون بسته بیرونی —
/// بسته spreadsheet برنامه وجود ندارد؛ فایل xlsx معتبر با package:archive
/// به‌صورت zip کاربرگ ساده با سلول inlineStr ساخته می‌شود).
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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

  // ── فاز ۹ — بند ۲۷: خروجی اکسل بدون بسته بیرونی ──────────────────────

  /// escape استاندارد XML برای متن سلول‌ها
  static String _xmlEsc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// سلول متنی با inlineStr — بدون sharedStrings (ساده و معتبر)
  static String _strCell(String ref, String text) =>
      '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
      '${_xmlEsc(text)}</t></is></c>';

  /// سلول رشته در ستون A تا C با ردیف r
  static String _rowCells(int r, String a, String b, String c) =>
      '<row r="$r">${_strCell('A$r', a)}${_strCell('B$r', b)}'
      '${_strCell('C$r', c)}</row>';

  /// ساخت بایت‌های یک فایل xlsx معتبر تک‌کاربرگی از رخدادهای روز.
  /// فایل xlsx در واقع یک zip است؛ کمینه اجزای لازم:
  /// [Content_Types].xml + _rels/.rels + workbook + rels + sheet1
  static List<int> buildXlsx(DateTime day, List<DailyReportEntry> entries) {
    final jdt = j.Jalali.fromDateTime(day);
    final title =
        'گزارش روزانه ${toPersianDigits('${jdt.year}/${jdt.month.toString().padLeft(2, '0')}/${jdt.day.toString().padLeft(2, '0')}')}';

    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main"><sheetData>');
    sb.write(_rowCells(1, 'گزارش روزانه برنامه J.S.H', '', ''));
    sb.write(_rowCells(2, title, '', ''));
    sb.write(_rowCells(3, 'ساعت', 'دسته', 'شرح'));
    var r = 4;
    for (final e in entries) {
      sb.write(_rowCells(r, e.time, e.category, e.text));
      r++;
    }
    sb.write(_rowCells(r, '', '', 'تعداد رخدادها: ${entries.length}'));
    sb.write('</sheetData></worksheet>');

    const contentTypes =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>';
    const rels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    const workbook =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="گزارش روزانه" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>';
    const workbookRels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>';

    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', rels))
      ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
      ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', workbookRels))
      ..addFile(ArchiveFile.string(
          'xl/worksheets/sheet1.xml', sb.toString()));
    return ZipEncoder().encode(archive);
  }

  /// نام فایل پایه با تاریخ شمسی — بند ۲۷
  static String _shamsiBaseName(DateTime day) {
    final jdt = j.Jalali.fromDateTime(day);
    return 'jsh-daily-'
        '${jdt.year}${jdt.month.toString().padLeft(2, '0')}${jdt.day.toString().padLeft(2, '0')}';
  }

  /// فاز ۹ — بند ۲۷: خروجی روزانه هم‌زمان txt و xlsx در Documents/JSH_reports
  /// خروجی: (مسیر txt، مسیر xlsx)
  static Future<(String, String)> exportBoth(
      DateTime day, List<DailyReportEntry> entries) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'JSH_reports');
    await Directory(dir).create(recursive: true);
    final base = _shamsiBaseName(day);
    final txtPath = p.join(dir, '$base.txt');
    final xlsxPath = p.join(dir, '$base.xlsx');
    await File(txtPath)
        .writeAsString(buildText(day, entries), encoding: utf8);
    await File(xlsxPath).writeAsBytes(buildXlsx(day, entries), flush: true);
    return (txtPath, xlsxPath);
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
