/// خروجی تقویم گوگل — قاعده ۳: فایل ICS سازگار با Google Calendar
/// (تقویم شمسی کبیسه را درست می‌سازد؛ ICS با تاریخ میلادی معادل صادر می‌شود
/// و در Google Calendar با «Import» اضافه می‌شود.)
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shamsi_date/shamsi_date.dart' as j;

import '../constants.dart';
import '../repos.dart';

class CalendarExportService {
  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}00';

  /// ساخت فایل ICS از موعدهای تحویل سفارش‌ها (سازگار Google Calendar)
  static Future<String> exportDeliveries({bool includeDelivered = false}) async {
    final tickets = await TicketRepo.all();
    final events = StringBuffer();
    events.write('BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//JSH//ServiceDashboard//FA\r\n'
        'CALSCALE:GREGORIAN\r\n'
        'METHOD:PUBLISH\r\n'
        'X-WR-CALNAME:داشبورد تعمیرات و خدمات — موعد تحویل\r\n'
        'X-WR-TIMEZONE:Asia/Tehran\r\n');

    for (final t in tickets) {
      if (!includeDelivered && t.status == TicketStatus.delivered) continue;
      final c = await CustomerRepo.byId(t.customerId);
      final due = t.dueDate;
      final dtStart = DateTime(due.year, due.month, due.day,
          int.tryParse(t.dueTime.split(':').first) ?? 18, 0);
      events.write('BEGIN:VEVENT\r\n'
          'UID:jsh-ticket-${t.id}@jsh.local\r\n'
          'DTSTAMP:${_fmt(DateTime.now())}\r\n'
          'DTSTART:${_fmt(dtStart)}\r\n'
          'DTEND:${_fmt(dtStart.add(const Duration(minutes: 30)))}\r\n'
          'SUMMARY:تحویل ${t.code} — ${c?.name ?? ''}\r\n'
          'DESCRIPTION:وضعیت: ${TicketStatus.labels[t.status] ?? t.status}\\n'
          'بیعانه: ${t.depositAmount} تومان\\n'
          'دستگاه: ${t.code}\r\n'
          'BEGIN:VALARM\r\n'
          'TRIGGER:PT0M\r\n'
          'ACTION:DISPLAY\r\n'
          'DESCRIPTION:موعد تحویل ${t.code}\r\n'
          'END:VALARM\r\n'
          'END:VEVENT\r\n');
    }
    events.write('END:VCALENDAR\r\n');

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
    await file.writeAsString(events.toString(), flush: true);
    return file.path;
  }
}
