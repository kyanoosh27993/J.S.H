/// سرویس جفت‌سازی گوشی با برنامه ویندوز (v0.12.4)
/// ---------------------------------------------------------------------------
/// روند جدید فعال‌سازی اندروید: گوشی به‌جای کد فعال‌سازی مستقل، با آدرس شبکه
/// لوکال برنامه ویندوزِ فعال (پورت 3000) و کد جفت‌سازی ۶ رقمی به آن وصل می‌شود
/// و توکن می‌گیرد. در هر ورودِ بعدی، توکن با PC تأیید می‌شود؛ PC مرجع اعتبار
/// لایسنس است (بند ۴) و بدون PC فعالِ در همان شبکه، برنامه گوشی راه‌اندازی نمی‌شود.
library;

import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../repos.dart';

/// نتیجه اتصال به PC
class PairResult {
  final bool ok;
  final String error;
  final String version;
  final bool licensed;
  final int daysLeft;
  const PairResult(
      {required this.ok,
      this.error = '',
      this.version = '',
      this.licensed = false,
      this.daysLeft = 0});
}

class PairService {
  PairService._();

  static const String keyHost = 'mobile_pc_host'; // مثال: 192.168.1.5:3000

  static Future<String?> host() async =>
      (await SettingsRepo.get(keyHost, '')).isEmpty
          ? null
          : await SettingsRepo.get(keyHost, '');

  static Future<String?> token() async {
    final t = await SettingsRepo.get('mobile_pc_token', '');
    return t.isEmpty ? null : t;
  }

  static Future<void> save(String host, String token) async {
    await SettingsRepo.set(keyHost, host.trim());
    await SettingsRepo.set('mobile_pc_token', token.trim());
  }

  /// جفت‌سازی اولیه — آدرس + کد ۶ رقمی نمایش‌داده‌شده روی PC
  static Future<PairResult> pair(String host, String pcCode) async {
    try {
      final r = await _post('http://$host/api/pair', {
        'pcCode': pcCode.trim(),
        'deviceName': 'اندروید ${Platform.operatingSystemVersion.split(' ').first}',
      });
      if (r['status'] != 200) {
        return PairResult(
            ok: false,
            error: (r['body']['error'] ?? 'کد جفت‌سازی اشتباه است').toString());
      }
      final token = (r['body']['token'] ?? '').toString();
      if (token.isEmpty) {
        return const PairResult(ok: false, error: 'پاسخ ناقص از PC');
      }
      await save(host, token);
      return PairResult(
          ok: true,
          version: (r['body']['version'] ?? '').toString());
    } catch (e) {
      return PairResult(
          ok: false,
          error: 'PC در این آدرس در دسترس نیست.\n'
              'برنامه ویندوز باید روشن و در همان Wi-Fi باشد.\n($e)');
    }
  }

  /// تأیید توکن در هر ورود — مرجع اعتبار لایسنس، برنامه ویندوز است
  static Future<PairResult> verify() async {
    final h = await host();
    final t = await token();
    if (h == null || t == null) {
      return const PairResult(ok: false, error: 'گوشی هنوز جفت نشده است');
    }
    try {
      final r = await _get('http://$h/api/verify?token=$t');
      if (r['status'] != 200) {
        return const PairResult(
            ok: false,
            error: 'جفت‌سازی نامعتبر است — دوباره جفت‌سازی کنید');
      }
      final licensed = r['body']['licensed'] == true;
      if (!licensed) {
        return const PairResult(
            ok: false,
            error: 'برنامه ویندوز فعال نیست یا اعتبارش تمام شده — '
                'اول ویندوز را فعال کنید');
      }
      return PairResult(
          ok: true,
          version: (r['body']['version'] ?? '').toString(),
          licensed: true,
          daysLeft: (r['body']['daysLeft'] ?? 0) as int);
    } catch (e) {
      return PairResult(
          ok: false,
          error: 'اتصال به PC برقرار نشد.\n'
              'برنامه ویندوز را روشن کنید و گوشی را به همان Wi-Fi وصل کنید.\n($e)');
    }
  }

  /// اسکن بارکد/QR → جستجوی سفارش روی PC
  static Future<List<Map<String, Object?>>> scan(String q) async {
    final h = await host();
    final t = await token();
    if (h == null || t == null) return const [];
    try {
      final r = await _get(
          'http://$h/api/scan?token=$t&q=${Uri.encodeComponent(q)}');
      if (r['status'] != 200) return const [];
      return ((r['body']['results'] ?? []) as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// آپلود عکس/سند به‌عنوان اتچ سفارش روی PC
  static Future<bool> uploadAttachment(
      int ticketId, List<int> bytes, String filename,
      {String note = ''}) async {
    final h = await host();
    final t = await token();
    if (h == null || t == null) return false;
    try {
      final hc = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await hc.postUrl(Uri.parse(
          'http://$h/api/attach?token=$t&ticket=$ticketId'
          '&note=${Uri.encodeComponent(note)}'));
      req.headers.set('x-filename', filename);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      return res.statusCode == 200 && body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── کلاینت HTTP کمکی ──
  static Future<Map<String, Object?>> _get(String url) async {
    final hc = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await hc.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    return {'status': res.statusCode, 'body': body};
  }

  static Future<Map<String, Object?>> _post(
      String url, Map<String, Object?> data) async {
    final hc = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await hc.postUrl(Uri.parse(url));
    final payload = jsonEncode(data);
    req.headers.contentType = ContentType.json;
    req.headers.contentLength = payload.length;
    req.write(payload);
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    return {'status': res.statusCode, 'body': body};
  }
}
