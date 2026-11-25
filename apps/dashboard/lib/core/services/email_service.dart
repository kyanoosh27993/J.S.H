/// سرویس ایمیل — ارسال SMTP + صف ارسال آفلاین + ساخت رویداد تقویمی ICS (F-06 + N-03)
library;

import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../repos.dart';

class SmtpConfig {
  String host;
  int port;
  bool ssl;
  String username;
  String password;
  String fromName;

  SmtpConfig({
    this.host = 'smtp.gmail.com',
    this.port = 465,
    this.ssl = true,
    this.username = '',
    this.password = '',
    this.fromName = 'داشبورد تعمیرات و خدمات',
  });

  bool get configured => username.isNotEmpty && password.isNotEmpty;

  Map<String, String> toJson() => {
        'host': host,
        'port': '$port',
        'ssl': ssl ? '1' : '0',
        'username': username,
        'password': password,
        'fromName': fromName,
      };

  static SmtpConfig fromJson(Map<String, String> j) => SmtpConfig(
        host: j['host'] ?? 'smtp.gmail.com',
        port: int.tryParse(j['port'] ?? '465') ?? 465,
        ssl: (j['ssl'] ?? '1') == '1',
        username: j['username'] ?? '',
        password: j['password'] ?? '',
        fromName: j['fromName'] ?? 'داشبورد تعمیرات و خدمات',
      );

  /// پیش‌تنظیم جیمیل برای سادگی راه‌اندازی (رمز برنامه ۱۶ رقمی گوگل)
  static SmtpConfig gmail(String email, String appPassword) => SmtpConfig(
        host: 'smtp.gmail.com',
        port: 465,
        ssl: true,
        username: email,
        password: appPassword,
      );
}

class EmailService {
  /// تخلیه صف ارسال — در شروع برنامه و هر ۳۰ ثانیه فراخوانی می‌شود
  static Future<int> drainQueue(SmtpConfig cfg) async {
    if (!cfg.configured) return 0;
    var sent = 0;
    final items = await EmailQueueRepo.pending(limit: 5);
    for (final row in items) {
      final id = row['id'] as int;
      try {
        await _sendOne(
          cfg,
          (row['to_addr'] ?? '') as String,
          (row['subject'] ?? '') as String,
          (row['body'] ?? '') as String,
          (row['attachment_path'] ?? '') as String,
          (row['ics_content'] ?? '') as String,
        );
        await EmailQueueRepo.markSent(id);
        sent++;
      } catch (e) {
        await EmailQueueRepo.markFailed(id, e.toString());
        // خطای شبکه: تلاش‌های بعدی در چرخه بعدی
        break;
      }
    }
    return sent;
  }

  static Future<void> _sendOne(
    SmtpConfig cfg,
    String to,
    String subject,
    String body,
    String attachmentPath,
    String icsContent,
  ) async {
    final server = cfg.ssl
        ? SmtpServer(cfg.host, port: cfg.port, username: cfg.username,
            password: cfg.password, ssl: true)
        : SmtpServer(cfg.host, port: cfg.port, username: cfg.username,
            password: cfg.password);

    final attachments = <Attachment>[];
    if (attachmentPath.isNotEmpty && File(attachmentPath).existsSync()) {
      attachments.add(FileAttachment(File(attachmentPath)));
    }
    if (icsContent.isNotEmpty) {
      // رویداد تقویم به‌صورت فایل موقت پیوست می‌شود
      final tmp = await Directory.systemTemp.createTemp('jsh_ics');
      final icsFile = File('${tmp.path}/reminder.ics');
      await icsFile.writeAsString(icsContent, flush: true);
      attachments.add(FileAttachment(icsFile));
    }

    final message = Message()
      ..from = Address(cfg.username, cfg.fromName)
      ..recipients.add(to)
      ..subject = subject
      ..text = body
      ..attachments.addAll(attachments);

    // در mailer 6، شکست ارسال به‌صورت Exception پرتاب می‌شود؛ رسیدن به اینجا = موفقیت
    await send(message, server);
  }

  /// ساخت محتوای رویداد تقویمی (ICS) — یادآوری در ساعت تنظیم‌شده کاربر
  static String buildIcs({
    required String uid,
    required DateTime start,
    required int durationMinutes,
    required String summary,
    required String description,
    int reminderMinutesBefore = 0,
  }) {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}T'
        '${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}00';

    final alarm = reminderMinutesBefore > 0
        ? 'BEGIN:VALARM\r\n'
            'TRIGGER:-PT${reminderMinutesBefore}M\r\n'
            'ACTION:DISPLAY\r\n'
            'DESCRIPTION:$summary\r\n'
            'END:VALARM\r\n'
        : '';

    return 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//JSH//ServiceDashboard//FA\r\n'
        'CALSCALE:GREGORIAN\r\n'
        'METHOD:REQUEST\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:$uid@jsh.local\r\n'
        'DTSTAMP:${fmt(DateTime.now())}\r\n'
        'DTSTART:${fmt(start)}\r\n'
        'DTEND:${fmt(start.add(Duration(minutes: durationMinutes)))}\r\n'
        'SUMMARY:$summary\r\n'
        'DESCRIPTION:$description\r\n'
        'BEGIN:VALARM\r\n'
        'TRIGGER:PT${reminderMinutesBefore}M\r\n'
        'ACTION:DISPLAY\r\n'
        'DESCRIPTION:$summary\r\n'
        'END:VALARM\r\n'
        '$alarm'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
  }
}
