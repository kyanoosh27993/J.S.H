/// سرویس اتصال موبایل (v0.12.4) — سرور HTTP لوکال روی پورت 3000 در برنامه ویندوز
/// ---------------------------------------------------------------------------
/// روند جدید فعال‌سازی اندروید:
/// ۱) برنامه ویندوز فعال و اجرا می‌شود؛ این سرور روی پورت 3000 بالا می‌آید.
/// ۲) گوشی در همان شبکه Wi-Fi آدرس (مثلاً http://192.168.1.5:3000) و کد جفت‌سازی
///    ۶ رقمی نمایش‌داده‌شده در صفحه «اتصال موبایل» را وارد می‌کند و توکن می‌گیرد.
/// ۳) از این پس ورود گوشی فقط با اتصال به همان شبکه و تأیید توکن انجام می‌شود —
///    اعتبار لایسنس ویندوز مرجع است (بند ۴ حفظ می‌شود).
/// ۴) دوربین گوشی به‌صورت آنلاین برای اسکن بارکد/QR و عکس‌برداری و ارسال اسناد
///    به‌عنوان اتچ سفارش استفاده می‌شود.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../db/db.dart';
import '../models.dart';
import '../repos.dart';
import '../constants.dart';
import 'activation_service.dart';
import 'app_session.dart';

/// وضعیت سرور اتصال موبایل — برای صفحه «اتصال موبایل»
class MobileLinkState {
  final bool running;
  final int port;
  final String? lanIp;
  final String pairingCode;
  final List<String> devices;
  final List<String> log;
  const MobileLinkState({
    required this.running,
    required this.port,
    this.lanIp,
    required this.pairingCode,
    this.devices = const [],
    this.log = const [],
  });
  String get url => lanIp == null ? 'http://<IP-سیستم>:$port' : 'http://$lanIp:$port';
}

/// سرور اتصال موبایل — فقط روی دسکتاپ (ویندوز) اجرا می‌شود
class MobileLinkService {
  MobileLinkService._();
  static HttpServer? _server;
  static String _pairingCode = '';
  static final Set<String> _tokens = <String>{};
  static final Map<String, String> _devices = <String, String>{}; // token → name
  static final List<String> _log = <String>[];

  static final ValueNotifier<MobileLinkState> state =
      ValueNotifier<MobileLinkState>(const MobileLinkState(
          running: false, port: 3000, pairingCode: ''));

  static void _emit(bool running, int port) {
    state.value = MobileLinkState(
      running: running,
      port: port,
      lanIp: running ? lanIp() : state.value.lanIp,
      pairingCode: _pairingCode,
      devices: _devices.values.toList(),
      log: List<String>.from(_log.take(40)),
    );
  }

  static void _addLog(String line) {
    _log.insert(0,
        '${DateTime.now().toIso8601String().substring(11, 19)} — $line');
    if (_log.length > 60) _log.removeLast();
    _emit(true, _server?.port ?? 3000);
  }

  /// نخستین IPv4 غیر loopback — آدرسی که گوشی باید وارد کند
  static String? lanIp() {
    try {
      final itfs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final itf in itfs) {
        for (final a in itf.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  static String _newCode() =>
      (Random.secure().nextInt(900000) + 100000).toString();

  static String _newToken() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// شروع سرور — [port] پیش‌فرض 3000؛ در تست‌ها 0 (پورت تصادفی)
  static Future<void> start({int port = 3000}) async {
    if (_server != null) return;
    _pairingCode = _newCode();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    _addLog('سرور روی پورت ${server.port} راه‌اندازی شد — کد جفت‌سازی: $_pairingCode');
    server.listen(_handle, onError: (_) {});
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _emit(false, 3000);
  }

  // ── پاسخ‌های JSON کمکی ──
  static void _json(HttpRequest req, int status, Object? obj) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(obj));
    req.response.close();
  }

  static Future<Map<String, dynamic>> _body(HttpRequest req) async {
    try {
      final s = await utf8.decoder.bind(req).join();
      return s.isEmpty ? <String, dynamic>{} : jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static void _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/') return _statusPage(req);
      if (path == '/api/pair' && req.method == 'POST') return _pair(req);
      // همه مسیرهای دیگر نیاز به توکن معتبر دارند
      final token = req.uri.queryParameters['token'] ??
          req.headers.value('x-jsh-token') ??
          '';
      if (!_tokens.contains(token)) {
        return _json(req, 401, {'ok': false, 'error': 'گوشی جفت‌سازی نشده است'});
      }
      if (path == '/api/verify') return _verify(req);
      if (path == '/api/status') return _status(req);
      if (path == '/api/search') return _search(req);
      if (path == '/api/attach' && req.method == 'POST') return _attach(req);
      if (path == '/api/scan') return _scan(req);
      return _json(req, 404, {'ok': false, 'error': 'مسیر یافت نشد'});
    } catch (e) {
      _json(req, 500, {'ok': false, 'error': '$e'});
    }
  }

  /// صفحه وضعیت — با مرورگر گوشی هم باز می‌شود تا صحت شبکه سریع‌تر چک شود
  static void _statusPage(HttpRequest req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html dir="rtl" lang="fa"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>J.S.H — اتصال موبایل</title></head>
<body style="font-family:Tahoma;text-align:center;padding:24px">
<h2>J.S.H — سرور اتصال موبایل فعال است</h2>
<p>این آدرس را در برنامه موبایل وارد کنید و کد جفت‌سازی را از صفحه
«اتصال موبایل» برنامه ویندوز بخوانید.</p>
</body></html>''');
    req.response.close();
  }

  /// جفت‌سازی — کد ۶ رقمی نمایش‌داده‌شده روی PC
  static void _pair(HttpRequest req) async {
    final b = await _body(req);
    final code = (b['pcCode'] ?? '').toString().trim();
    final name = (b['deviceName'] ?? 'گوشی').toString();
    if (code != _pairingCode) {
      _addLog('جفت‌سازی ناموفق — کد اشتباه از $name');
      return _json(req, 401, {'ok': false, 'error': 'کد جفت‌سازی اشتباه است'});
    }
    final token = _newToken();
    _tokens.add(token);
    _devices[token] = name;
    _addLog('جفت‌سازی موفق: $name');
    _json(req, 200, {'ok': true, 'token': token, 'version': AppInfo.version});
  }

  /// بررسی اعتبار توکن + وضعیت لایسنس PC (مرجع فعال‌سازی گوشی — بند ۴)
  static void _verify(HttpRequest req) {
    final s = AppSession.I;
    final active = s.activationStatus == ActivationStatus.active && !s.locked;
    _json(req, 200, {
      'ok': true,
      'version': AppInfo.version,
      'licensed': active,
      'daysLeft': active ? ActivationService.remainingDays(s.license) : 0,
    });
  }

  /// وضعیت کوتاه برای صفحه اصلی گوشی
  static void _status(HttpRequest req) {
    _json(req, 200, {'ok': true, 'app': AppInfo.appName, 'version': AppInfo.version});
  }

  /// جستجوی سفارش برای اسکن بارکد/QR — q = کد رسید/سریال/تلفن/نام
  static void _search(HttpRequest req) async {
    final q = (req.uri.queryParameters['q'] ?? '').trim();
    if (q.isEmpty) return _json(req, 400, {'ok': false, 'error': 'عبارت جستجو خالی است'});
    final all = await TicketRepo.all();
    final nameMap = await CustomerRepo.nameMap();
    final dbq = await Db.instance();
    final devices = {
      for (final row in await dbq.query('devices'))
        (row['id'] as int): Device.fromMap(row)
    };
    final hits = all.where((t) {
      final cust = nameMap[t.customerId] ?? '';
      final dev = devices[t.deviceId];
      return t.code.contains(q) ||
          (dev?.serial ?? '').contains(q) ||
          cust.contains(q);
    }).take(10).map((t) => <String, Object?>{
          'id': t.id,
          'code': t.code,
          'customer': nameMap[t.customerId] ?? '',
          'model': devices[t.deviceId]?.model ?? '',
          'serial': devices[t.deviceId]?.serial ?? '',
          'status': t.status,
        }).toList();
    _json(req, 200, {'ok': true, 'results': hits});
  }

  /// اسکن بارکد — میان‌بر همان جستجو با ثبت لاگ
  static void _scan(HttpRequest req) async {
    final q = (req.uri.queryParameters['q'] ?? '').trim();
    _addLog('اسکن از گوشی: $q');
    _search(req);
  }

  /// آپلود عکس/سند برای اتچ سفارش — بدنه خام فایل با هدرهای نام و شناسه
  static void _attach(HttpRequest req) async {
    final ticketId = int.tryParse(req.uri.queryParameters['ticket'] ?? '');
    final note = (req.uri.queryParameters['note'] ?? '').trim();
    final filename = (req.headers.value('x-filename') ??
            'mobile_${DateTime.now().millisecondsSinceEpoch}.jpg')
        .replaceAll(RegExp(r'[^\w\.\-ا-ی ]'), '_');
    if (ticketId == null) {
      return _json(req, 400, {'ok': false, 'error': 'شناسه سفارش نامعتبر است'});
    }
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      return _json(req, 400, {'ok': false, 'error': 'فایل خالی است'});
    }
    final dir = await _uploadDir();
    final f = File('${dir.path}$platformSep$filename');
    var path = f.path;
    var i = 1;
    while (f.existsSync()) {
      path = '${f.path.replaceAll(RegExp(r'\.\w+$'), '')}_$i'
          '${RegExp(r'\.\w+$').firstMatch(filename)?.group(0) ?? '.jpg'}';
      i++;
    }
    await File(path).writeAsBytes(bytes);
    final db = await Db.instance();
    await db.insert('attachments', {
      'ticket_id': ticketId,
      'path': path,
      'kind': 'photo',
      'note': note.isEmpty ? 'ارسال از موبایل' : note,
      'created_at': DateTime.now().toIso8601String(),
    });
    _addLog('اتچ از گوشی برای سفارش #$ticketId — $filename');
    _json(req, 200, {'ok': true, 'path': path});
  }

  static String get platformSep => Platform.pathSeparator;

  static Future<Directory> _uploadDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}mobile_uploads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
