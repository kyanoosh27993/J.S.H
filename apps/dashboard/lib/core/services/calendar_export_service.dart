/// خروجی تقویم گوگل — قاعده ۳: فایل ICS سازگار با Google Calendar
/// (تقویم شمسی کبیسه را درست می‌سازد؛ ICS با تاریخ میلادی معادل صادر می‌شود
/// و در Google Calendar با «Import» اضافه می‌شود.)
/// فاز ۳: منطقه‌زمانی صریح Asia/Tehran (+03:30 ثابت — ایران از ۱۴۰۱ بدون ساعت تابستانی)
/// + فیلتر بازه تاریخ + مدل دستگاه در توضیحات + escape استاندارد RFC 5545.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shamsi_date/shamsi_date.dart' as j;

import '../constants.dart';
import '../repos.dart';
import '../utils.dart';

class CalendarExportService {
  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}00';

  /// استاندارد RFC 5545: کاراکترهای ویژه در مقادیر متنی escape می‌شوند
  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');

  static const _vtimezone =
      'BEGIN:VTIMEZONE\r\n'
      'TZID:Asia/Tehran\r\n'
      'BEGIN:STANDARD\r\n'
      'DTSTART:19700101T000000\r\n'
      'TZOFFSETFROM:+0330\r\n'
      'TZOFFSETTO:+0330\r\n'
      'TZNAME:IRST\r\n'
      'END:STANDARD\r\n'
      'END:VTIMEZONE\r\n';

  /// ساخت متن ICS — بازه اختیاری: فقط سفارش‌هایی که موعد تحویل‌شان داخل بازه است
  static Future<String> buildIcs({
    bool includeDelivered = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final tickets = await TicketRepo.all();
    final events = StringBuffer();
    events.write('BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//JSH//ServiceDashboard//FA\r\n'
        'CALSCALE:GREGORIAN\r\n'
        'METHOD:PUBLISH\r\n'
        'X-WR-CALNAME:داشبورد تعمیرات و خدمات — موعد تحویل\r\n'
        'X-WR-TIMEZONE:Asia/Tehran\r\n');
    events.write(_vtimezone);

    for (final t in tickets) {
      if (!includeDelivered && t.status == TicketStatus.delivered) continue;
      final due = t.dueDate;
      final dayOnly = DateTime(due.year, due.month, due.day);
      if (from != null &&
          dayOnly.isBefore(DateTime(from.year, from.month, from.day))) {
        continue;
      }
      if (to != null && dayOnly.isAfter(DateTime(to.year, to.month, to.day))) {
        continue;
      }
      final c = await CustomerRepo.byId(t.customerId);
      final d = await DeviceRepo.byId(t.deviceId);
      final dtStart = DateTime(due.year, due.month, due.day,
          int.tryParse(t.dueTime.split(':').first) ?? 18, 0);
      events.write('BEGIN:VEVENT\r\n'
          'UID:jsh-ticket-${t.id}@jsh.local\r\n'
          'DTSTAMP;TZID=Asia/Tehran:${_fmt(DateTime.now())}\r\n'
          'DTSTART;TZID=Asia/Tehran:${_fmt(dtStart)}\r\n'
          'DTEND;TZID=Asia/Tehran:${_fmt(dtStart.add(const Duration(minutes: 30)))}\r\n'
          'SUMMARY:تحویل ${_esc(t.code)} — ${_esc(c?.name ?? '')}\r\n'
          'DESCRIPTION:وضعیت: ${_esc(TicketStatus.labels[t.status] ?? t.status)}\\n'
          'دستگاه: ${_esc(d?.model ?? '')}\\n'
          'بیعانه: ${_esc(toPersianDigits('${t.depositAmount}'))} تومان\\n'
          'موعد شمسی: ${_esc(shamsiDate(due))} ${_esc(toPersianDigits(t.dueTime))}\r\n'
          'BEGIN:VALARM\r\n'
          'TRIGGER:PT0M\r\n'
          'ACTION:DISPLAY\r\n'
          'DESCRIPTION:موعد تحویل ${_esc(t.code)}\r\n'
          'END:VALARM\r\n'
          'END:VEVENT\r\n');
    }
    events.write('END:VCALENDAR\r\n');
    return events.toString();
  }

  /// نوشتن فایل در پوشه اسناد — خروجی قابل Import در Google Calendar
  static Future<String> exportDeliveries({
    bool includeDelivered = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final content =
        await buildIcs(includeDelivered: includeDelivered, from: from, to: to);
    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'calendar_export');
    await Directory(dir).create(recursive: true);
    final now = j.Jalali.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${DateTime.now().hour.toString().padLeft(2, '0')}'
        '${DateTime.now().minute.toString().padLeft(2, '0')}';
    final file = File(p.join(dir, 'jsh_deliveries_$stamp.ics'));
    await file.writeAsString(content, flush: true);
    return file.path;
  }
}
