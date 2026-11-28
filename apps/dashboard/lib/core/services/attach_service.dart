/// اتچ عکس سلامت کالا + دوربین گوشی روی وای‌فای — فاز ۸ (بند ۷ جدید)
/// - انتخاب تصویر از فایل/گالری با file_selector (ویندوز + اندروید)
/// - سرور HTTP محلی (بدون وابستگی بیرونی) روی وای‌فای: کاربر با گوشی به
///   آدرس نمایش‌داده‌شده می‌رود، عکس می‌گیرد/انتخاب می‌کند و ارسال می‌شود؛
///   عکس به سفارش جاری اتچ می‌شود. همه‌چیز آفلاین روی شبکه داخلی.
/// فاز ۶ب:
/// - بند ۱۰: اتچ عکس با دوربین/گالری گوشی (image_picker) + بازکردن فایل
///   با نمایشگر سیستم (برای چاپ/نمایش روی رایانه)
/// - بند ۴: ارسال عکس روی وای‌فای فقط با کد فعال‌سازی معتبر رایانه
///   (هدر X-JSH-License) پذیرفته می‌شود — LicenseGateService
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/db.dart';
import 'license_gate_service.dart';
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
    final (err, _) = await _storeAndRecord(ticketId, await file.readAsBytes(),
        p.extension(file.path).toLowerCase(), note);
    return err;
  }

  /// بند ۱۰/۱۹ — گرفتن عکس با دوربین گوشی یا انتخاب از گالری (image_picker).
  /// روی رایانه UnsupportedError می‌دهد (فراخوان پیام «فقط موبایل» می‌دهد).
  /// خروجی: مسیر فایل ذخیره‌شده؛ null یعنی کاربر انصراف داد؛
  /// خطای اعتبارسنجی تصویر با Exception بالا می‌آید.
  static Future<String?> attachFromCamera(int ticketId,
      {bool fromGallery = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('دوربین/گالری فقط روی موبایل');
    }
    final picked = await ImagePicker().pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 80,
    );
    if (picked == null) return null; // کاربر انصراف داد
    final (err, path) = await _storeAndRecord(
        ticketId,
        await picked.readAsBytes(),
        p.extension(picked.path).toLowerCase(),
        fromGallery ? 'از گالری' : 'از دوربین');
    if (err != null) throw Exception(err);
    return path;
  }

  /// بازکردن فایل با نمایشگر سیستم — برای دیدن/چاپ رسید و عکس‌ها روی رایانه.
  /// روی گوشی در دسترس نیست (فراخوان پیام مناسب می‌دهد).
  /// بند ۱۰.۶۳ — ویرایش توضیح یک عکس اتچ‌شده
  static Future<void> updateNote(int attachId, String note) async {
    final db = await Db.instance();
    await db.update('attachments', {'note': note},
        where: 'id = ?', whereArgs: [attachId]);
    await AuditRepo.log('attach_note', 'توضیح اتچ #$attachId ویرایش شد');
  }

  static Future<void> openSystem(String filePath) async {
    if (Platform.isWindows) {
      // explorer.exe ساده‌تر و امن‌تر از cmd /c start است (نیازی به shell نیست)
      await Process.run('explorer.exe', [filePath], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.run('open', [filePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [filePath]);
    } else {
      throw UnsupportedError('چاپ/بازکردن سیستم روی گوشی در دسترس نیست');
    }
  }

  static Future<String> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'attachments', '$ticketFolderBase');
    return dir;
  }

  static String ticketFolderBase = '';

  /// ذخیره بایت‌ها + رکورد بانک —
  /// خروجی: (متن خطا یا null، مسیر فایل ذخیره‌شده یا null در خطا)
  static Future<(String?, String?)> _storeAndRecord(
      int ticketId, List<int> bytes, String ext, String note) async {
    final fixedExt = (ext == '.jpg' || ext == '.jpeg') ? '.jpg' : '.png';
    // اعتبارسنجی PNG/JPEG — تصویر خراب هرگز ذخیره نمی‌شود
    if (bytes.length < 8) return ('فایل تصویر معتبر نیست', null);
    final isPng =
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!isPng && !isJpeg) {
      return ('فقط تصویر PNG یا JPEG پذیرفته می‌شود', null);
    }
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
    return (null, target);
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
        // بند ۴ — دروازه اعتبارسنجی: هر ارسال عکس فقط با کد فعال‌سازی
        // معتبر رایانه پذیرفته می‌شود (کد در هدر X-JSH-License می‌آید)
        final lic = req.headers.value('x-jsh-license');
        final licenseOk = await LicenseGateService.validate(lic);
        if (!licenseOk) {
          final missing = lic == null || lic.trim().isEmpty;
          await AuditRepo.log(
              'wifi_license_reject',
              missing
                  ? 'ارسال عکس بدون کد فعال‌سازی رایانه — سفارش #$ticketId'
                  : 'ارسال عکس با کد فعال‌سازی نامعتبر/منقضی — سفارش #$ticketId');
          // تخلیه بدنه تا مرورگر پاسخ ۴۰۳ را کامل دریافت کند
          try {
            await req.drain<void>();
          } catch (_) {}
          req.response.statusCode = 403;
          req.response.headers.contentType = ContentType.html;
          req.response.write('<meta charset="utf-8">'
              '<body style="font-family:sans-serif" dir="rtl">'
              '<h2>ارسال عکس رد شد ✋</h2>'
              '<p>${missing ? 'کد فعال‌سازی رایانه وارد نشده است' : 'کد فعال‌سازی رایانه نامعتبر، منقضی یا غیرفعال است'}</p>'
              '<p>کد فعال‌سازی برنامه رایانه را در فیلد بالای این صفحه وارد کنید؛'
              ' اگر اعتبار برنامه تمام شده، در برنامه رایانه تمدید کنید.</p>'
              '<a href="/">بازگشت</a></body>');
          await req.response.close();
          return;
        }
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
        final (err, _) = await AttachService._storeAndRecord(
            ticketId, img, '.jpg', 'از گوشی (وای‌فای)');
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

  /// صفحه HTML گوشی — بند ۴: کد فعال‌سازی رایانه در فیلد متن (ذخیره در
  /// localStorage با کلید jsh_license) و ارسال با fetch و هدر X-JSH-License
  String _page() => '''<!doctype html><html dir="rtl" lang="fa"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ارسال عکس سلامت کالا — J.S.H</title>
<style>body{font-family:Vazirmatn,Tahoma,sans-serif;background:#f4f6fb;padding:24px;text-align:center}
.c{max-width:420px;margin:0 auto;background:#fff;border-radius:16px;padding:24px;box-shadow:0 4px 18px #0001}
input[type=file]{width:100%;margin:12px 0}
#lic{width:100%;box-sizing:border-box;margin:8px 0;padding:10px;border:1px solid #cbd5e1;border-radius:10px;font-size:15px;text-align:center}
button{width:100%;padding:12px;border:0;border-radius:10px;background:#2563eb;color:#fff;font-size:16px}
h2{color:#1e293b}.lbl{color:#334155;font-size:14px;font-weight:bold}
#result a{display:inline-block;margin-top:8px;padding:10px 16px;background:#e2e8f0;border-radius:10px;color:#1e293b;text-decoration:none}</style>
</head><body><div class="c">
<h2>ارسال عکس سلامت کالا</h2>
<p>سفارش: ${'$ticketId'} — عکس را بگیرید یا از گالری انتخاب کنید.</p>
<div class="lbl">کد فعال‌سازی برنامه رایانه را وارد کنید</div>
<input type="text" id="lic" placeholder="JSH-XXXXXX-XXXXXX-..." autocomplete="off">
<input type="file" id="photo" name="photo" accept="image/*">
<p style="color:#555;font-size:13px">از گالری انتخاب کنید یا با دوربین عکس بگیرید — هر دو ممکن است.</p>
<button type="button" onclick="send()">ارسال عکس</button>
<div id="result"></div>
<script>
(function(){
  var lic = document.getElementById('lic');
  lic.value = localStorage.getItem('jsh_license') || '';
  lic.addEventListener('input', function(){
    localStorage.setItem('jsh_license', lic.value.trim());
  });
})();
async function send(){
  var f = document.getElementById('photo');
  var out = document.getElementById('result');
  if(!f.files.length){
    out.innerHTML = '<p style="color:#b91c1c">ابتدا عکس را انتخاب کنید</p>';
    return;
  }
  var fd = new FormData();
  fd.append('photo', f.files[0]);
  var lic = localStorage.getItem('jsh_license') || '';
  try{
    var r = await fetch('/upload', {method:'POST', headers:{'X-JSH-License': lic}, body: fd});
    out.innerHTML = await r.text();
  }catch(e){
    out.innerHTML = '<p style="color:#b91c1c">خطا در ارسال عکس — دوباره تلاش کنید</p>';
  }
}
</script>
<p style="color:#64748b;font-size:13px">عکس مستقیم روی رایانه فروشگاه ذخیره می‌شود — بدون اینترنت، فقط وای‌فای داخلی.</p>
</div></body></html>''';
}

/// ابزار داخلی
class Uint8ListSafe {
  final List<int> bytes;
  const Uint8ListSafe._(this.bytes);
  static Uint8ListSafe from(List<int> b) => Uint8ListSafe._(b);
}
