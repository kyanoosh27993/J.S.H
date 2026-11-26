/// اتچ عکس سلامت کالا + دوربین گوشی روی وای‌فای — فاز ۸ (بند ۷ جدید)
/// - انتخاب تصویر از فایل/گالری با file_selector (ویندوز + اندروید)
/// - سرور HTTP محلی (بدون وابستگی بیرونی) روی وای‌فای: کاربر با گوشی به
///   آدرس نمایش‌داده‌شده می‌رود، عکس می‌گیرد/انتخاب می‌کند و ارسال می‌شود؛
///   عکس به سفارش جاری اتچ می‌شود. همه‌چیز آفلاین روی شبکه داخلی.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/db.dart';
import 'supervisor_service.dart' show AuditRepo;

class AttachService {
  /// فهرست عکس‌های سفارش
  static Future<List<Map<String, Object?>>> list(int ticketId) async {
    final db = await Db.instance();
    return db.query('attachments',
        where: 'ticket_id = ?',
        whereArgs: [ticketId],
        orderBy: 'id DESC');
  }

  /// افزودن از فایل — کپی در پوشه برنامه + ثبت در بانک
  static Future<String?> attachFromFile(int ticketId, {String note = ''}) async {
    const typeGroup = XTypeGroup(
      label: 'تصویر',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return null;
    return _storeAndRecord(ticketId, await file.readAsBytes(),
        p.extension(file.path).toLowerCase(), note);
  }

  static Future<String> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'attachments', '$ticketFolderBase');
    return dir;
  }

  static String ticketFolderBase = '';

  /// ذخیره بایت‌ها + رکورد بانک
  static Future<String?> _storeAndRecord(
      int ticketId, List<int> bytes, String ext, String note) async {
    final fixedExt = (ext == '.jpg' || ext == '.jpeg') ? '.jpg' : '.png';
    // اعتبارسنجی PNG/JPEG — تصویر خراب هرگز ذخیره نمی‌شود
    if (bytes.length < 8) return 'فایل تصویر معتبر نیست';
    final isPng =
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!isPng && !isJpeg) return 'فقط تصویر PNG یا JPEG پذیرفته می‌شود';
    ticketFolderBase = '$ticketId';
    final dir = await _dir();
    await Directory(dir).create(recursive: true);
    final name =
        '${DateTime.now().millisecondsSinceEpoch}$fixedExt';
    final target = p.join(dir, name);
    await File(target).writeAsBytes(bytes);
    final db = await Db.instance();
    await db.insert('attachments', {
      'ticket_id': ticketId,
      'path': target,
      'kind': 'photo',
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    await AuditRepo.log('attach_add', 'عکس سلامت کالا به سفارش #$ticketId اتچ شد');
    return null;
  }

  /// حذف اتچ — بند ۱۷ (مدیریت کامل از داخل برنامه)
  static Future<void> delete(int attachId) async {
    final db = await Db.instance();
    final rows =
        await db.query('attachments', where: 'id = ?', whereArgs: [attachId], limit: 1);
    if (rows.isNotEmpty) {
      try {
        final f = File((rows.first['path'] ?? '') as String);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await db.delete('attachments', where: 'id = ?', whereArgs: [attachId]);
    await AuditRepo.log('attach_delete', 'حذف عکس #$attachId');
  }
}

/// سرور دریافت عکس از گوشی روی وای‌فای — بند ۷ جدید
/// کاربر گوشی را به همان وای‌فای وصل می‌کند؛ آدرس مثل http://192.168.1.5:8899
/// در مرورگر گوشی باز می‌شود؛ فرم ارسال عکس → ذخیره در سفارش جاری.
class WifiPhotoServer {
  HttpServer? _server;
  int ticketId = 0;
  int received = 0;
  String? lastError;

  bool get running => _server != null;

  Future<String> start(int forTicketId) async {
    ticketId = forTicketId;
    final ip = await _localIp();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8899);
    _server!.listen(_handle);
    await AuditRepo.log(
        'wifi_server', 'سرور دریافت عکس گوشی برای سفارش #$forTicketId روشن شد');
    return 'http://$ip:8899';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String> _localIp() async {
    final interfaces = await NetworkInterface.list();
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback && a.type == InternetAddressType.IPv4) {
          return a.address;
        }
      }
    }
    return '127.0.0.1';
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_page());
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/upload') {
        final bytes = <int>[];
        await for (final chunk in req) {
          bytes.addAll(chunk);
        }
        // بدنه multipart — استخراج بایت تصویر بین دو مرز
        final data = Uint8ListSafe.from(bytes);
        final img = _extractImage(data);
        if (img == null) {
          lastError = 'تصویری در ارسال پیدا نشد';
          req.response.statusCode = 400;
          await req.response.close();
          return;
        }
        final err = await AttachService._storeAndRecord(ticketId, img, '.jpg', 'از گوشی (وای‌فای)');
        received++;
        req.response.statusCode = err == null ? 200 : 400;
        req.response.headers.contentType = ContentType.html;
        req.response.write('<meta charset="utf-8"><body style="font-family:sans-serif">'
            '<h2>${err == null ? 'عکس دریافت و اتچ شد ✔' : 'خطا: $err'}</h2>'
            '<a href="/">بازگشت و ارسال عکس بعدی</a></body>');
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (e) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// استخراج بزرگ‌ترین بخش تصویری از بدنه multipart
  static List<int>? _extractImage(Uint8ListSafe data) {
    final b = data.bytes;
    // JPEG: FF D8 ... FF D9
    int? start;
    int? end;
    for (var i = 0; i < b.length - 1; i++) {
      if (b[i] == 0xFF && b[i + 1] == 0xD8) {
        start = i;
        break;
      }
    }
    if (start != null) {
      for (var i = b.length - 2; i > start; i--) {
        if (b[i] == 0xFF && b[i + 1] == 0xD9) {
          end = i + 2;
          break;
        }
      }
    }
    if (start != null && end != null && end - start > 100) {
      return b.sublist(start, end);
    }
    // PNG: 89 50 4E 47
    for (var i = 0; i < b.length - 4; i++) {
      if (b[i] == 0x89 && b[i + 1] == 0x50 && b[i + 2] == 0x4E && b[i + 3] == 0x47) {
        return b.sublist(i, b.length);
      }
    }
    return null;
  }

  String _page() => '''<!doctype html><html dir="rtl" lang="fa"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ارسال عکس سلامت کالا — J.S.H</title>
<style>body{font-family:Vazirmatn,Tahoma,sans-serif;background:#f4f6fb;padding:24px;text-align:center}
.c{max-width:420px;margin:0 auto;background:#fff;border-radius:16px;padding:24px;box-shadow:0 4px 18px #0001}
input[type=file]{width:100%;margin:12px 0}button{width:100%;padding:12px;border:0;border-radius:10px;background:#2563eb;color:#fff;font-size:16px}
h2{color:#1e293b}</style></head><body><div class="c">
<h2>ارسال عکس سلامت کالا</h2>
<p>سفارش: ${'$ticketId'} — عکس را بگیرید یا از گالری انتخاب کنید.</p>
<form action="/upload" method="post" enctype="multipart/form-data">
<input type="file" name="photo" accept="image/*" capture="environment" required>
<button type="submit">ارسال عکس</button>
</form>
<p style="color:#64748b;font-size:13px">عکس مستقیم روی رایانه فروشگاه ذخیره می‌شود — بدون اینترنت، فقط وای‌فای داخلی.</p>
</div></body></html>''';
}

/// ابزار داخلی
class Uint8ListSafe {
  final List<int> bytes;
  const Uint8ListSafe._(this.bytes);
  static Uint8ListSafe from(List<int> b) => Uint8ListSafe._(b);
}
