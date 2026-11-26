/// موتور کد فعال‌سازی J.S.H — بسته مشترک برنامه اصلی و برنامه جانبی تولید کد
///
/// ساختار کد (متصل به دستگاه):
///   payload  = magic(1) + version(1) + expiryDays(3) + maxReinstalls(1) + deviceHash(8)
///   code     = base32(payload + HMAC-SHA256(payload, key)[0..8])
///
/// • expiryDays: روزهای سپری‌شده از epoch میلادی تا پایان اعتبار (۳ بایت — تا سال ۲۱۶۷)
/// • maxReinstalls: سقف نصب مجدد روی همان دستگاه (۰ = پیش‌فرض برنامه)
/// • deviceHash = SHA-256('JSH-DEV|' + deviceId) — ۸ بایت اول؛ کد فقط روی همان دستگاه کار می‌کند
///
/// ضد هک (بند ۳ درخواست صاحب پروژه):
///   • امضای HMAC — دستکاری هر بایت از کد یا تاریخ اعتبار رد می‌شود
///   • اتصال به اثر انگشت مادربورد + CPU — کد روی دستگاه دیگر بی‌ارزش است
///   • هوشمند ضد تاریخ: بررسی تاریخ در سرویس برنامه (lastSeen monotonic) — عقب‌بردن
///     تاریخ سیستم اعتبار را طولانی نمی‌کند
///   • کلید HMAC در سورس با درهم‌ریزی بایت ذخیره می‌شود (بالا بردن هزینه تحلیل استاتیک)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// الفبای انسان‌پسند base32 — بدون I, L, O, U (رد نشدن حروف مشابه)
const String kBase32Alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

const int kMagicByte = 0x4A; // 'J'
const int kVersionByte = 0x01;
const int kPayloadLen = 14; // 1+1+3+1+8
const int kMacLen = 8;
const int kTotalLen = kPayloadLen + kMacLen; // 22

/// نتیجه اعتبارسنجی کد فعال‌سازی
enum ActivationCheck {
  ok,
  badFormat,
  tampered, // امضای HMAC درست نیست
  wrongDevice, // کد مال دستگاه دیگری است
  expired, // تاریخ اعتبار تمام شده
  wrongVersion,
}

class ActivationResult {
  final ActivationCheck check;
  final DateTime? expiry; // فقط در حالت ok پر می‌شود
  final int maxReinstalls; // ۰ = پیش‌فرض برنامه

  const ActivationResult(this.check, {this.expiry, this.maxReinstalls = 0});
  bool get ok => check == ActivationCheck.ok;
}

class ActivationCodec {
  ActivationCodec._();

  /// کلید HMAC — از قطعه‌های درهم‌ریخته در زمان اجرا ساخته می‌شود.
  /// هر تغییر این قطعه‌ها در سورس، همه کدهای صادرشده قبلی را باطل می‌کند.
  static Uint8List _key() {
    // قطعه‌های خام (XOR با ماسک در زمان اجرا)
    const mask = 0x5C;
    final p1 = <int>[0x39, 0x2e, 0x1f, 0x28, 0x33, 0x3f, 0x2c, 0x1e];
    final p2 = <int>[0x61, 0x5f, 0x33, 0x6a, 0x40, 0x29, 0x66, 0x35];
    final p3 = <int>[0x08, 0x6c, 0x14, 0x58, 0x3d, 0x71, 0x0b, 0x4f];
    final bytes = <int>[];
    for (var i = 0; i < 8; i++) {
      bytes.add((p1[i] ^ mask) & 0xFF);
      bytes.add((p2[i] ^ mask) & 0xFF);
      bytes.add((p3[i] ^ mask) & 0xFF);
    }
    // پیوند با نمک ثابت برنامه
    final salt = utf8.encode('JSH::AVRIN_SEGAL::ACTIVATION::1405');
    final combined = <int>[...bytes, ...salt];
    return Uint8List.fromList(
        sha256.convert(combined).bytes);
  }

  /// هش ۸ بایتی دستگاه — کد فقط برای همین hash معتبر است
  static Uint8List deviceHash(String deviceId) {
    final h = sha256.convert(utf8.encode('JSH-DEV|$deviceId')).bytes;
    return Uint8List.fromList(h.sublist(0, 8));
  }

  /// نمایش خلاصه‌شده شناسه دستگاه برای ثبت در گزارش (۸ کاراکتر اول هش)
  static String shortDeviceId(String deviceId) =>
      deviceHash(deviceId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()
          .substring(0, 8).toUpperCase();

  static int _epochDays(DateTime dt) =>
      dt.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;

  static DateTime _fromEpochDays(int days) =>
      DateTime.utc(1970, 1, 1).add(Duration(days: days));

  /// ساخت کد فعال‌سازی
  /// [expiry]: تاریخ پایان اعتبار (ساعت ۱۲ ظهر برای پایداری در منطقه‌های زمانی)
  /// [deviceId]: شناسه کامل دستگاه (خروجی LicenseService.fingerprint)
  /// [maxReinstalls]: سقف نصب مجدد روی همان دستگاه — ۰ یعنی پیش‌فرض برنامه (۳ بار)
  static String generate({
    required DateTime expiry,
    required String deviceId,
    int maxReinstalls = 0,
  }) {
    final expDays = _epochDays(expiry);
    if (expDays <= 0 || expDays > 0xFFFFFF) {
      throw ArgumentError('تاریخ اعتبار خارج از بازه مجاز است');
    }
    final payload = BytesBuilder();
    payload.addByte(kMagicByte);
    payload.addByte(kVersionByte);
    final e = expDays;
    payload.addByte((e >> 16) & 0xFF);
    payload.addByte((e >> 8) & 0xFF);
    payload.addByte(e & 0xFF);
    payload.addByte(maxReinstalls.clamp(0, 255));
    payload.add(deviceHash(deviceId));
    final mac = Hmac(sha256, _key())
        .convert(payload.toBytes())
        .bytes
        .sublist(0, kMacLen);
    final all = <int>[...payload.toBytes(), ...mac];
    return _format(_base32Encode(all));
  }

  /// اعتبارسنجی کامل کد نسبت به دستگاه و تاریخ امروز
  /// [today]: تاریخ فعلی سیستم — در برنامه واقعی Date.now
  /// [lastSeen]: بیشینه تاریخ دیده‌شده قبلی (ضد عقب‌بردن تاریخ) — خالی یعنی نصب تازه
  static ActivationResult verify({
    required String code,
    required String deviceId,
    required DateTime today,
    DateTime? lastSeen,
  }) {
    final normalized = _normalize(code);
    if (normalized == null || normalized.length != 36) {
      return const ActivationResult(ActivationCheck.badFormat);
    }
    final bytes = _base32Decode(normalized);
    if (bytes == null || bytes.length != kTotalLen) {
      return const ActivationResult(ActivationCheck.badFormat);
    }
    final payload = bytes.sublist(0, kPayloadLen);
    final mac = bytes.sublist(kPayloadLen);
    final expected = Hmac(sha256, _key())
        .convert(payload)
        .bytes
        .sublist(0, kMacLen);
    if (!_constTimeEq(mac, expected)) {
      return const ActivationResult(ActivationCheck.tampered);
    }
    if (payload[0] != kMagicByte) {
      return const ActivationResult(ActivationCheck.badFormat);
    }
    if (payload[1] != kVersionByte) {
      return const ActivationResult(ActivationCheck.wrongVersion);
    }
    final expDays = (payload[2] << 16) | (payload[3] << 8) | payload[4];
    final expiry = _fromEpochDays(expDays);
    final maxRe = payload[5];
    final dh = Uint8List.fromList(payload.sublist(6, 14));
    final dh2 = deviceHash(deviceId);
    for (var i = 0; i < 8; i++) {
      if (dh[i] != dh2[i]) {
        return const ActivationResult(ActivationCheck.wrongDevice);
      }
    }
    // تاریخ: امروز یا بیشینه تاریخ دیده‌شده نباید از اعتبار گذشته باشد
    final effectiveToday = _maxDay(today, lastSeen);
    if (_epochDays(effectiveToday) > expDays) {
      return ActivationResult(ActivationCheck.expired,
          expiry: expiry, maxReinstalls: maxRe);
    }
    return ActivationResult(ActivationCheck.ok,
        expiry: expiry, maxReinstalls: maxRe);
  }

  static DateTime _maxDay(DateTime a, DateTime? b) {
    if (b == null) return a;
    return b.isAfter(a) ? b : a;
  }

  static bool _constTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// حذف پیشوند و جداکننده‌ها + تبدیل حروف مشابه
  static String? _normalize(String raw) {
    var s = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-–—]'), '');
    if (s.startsWith('JSH')) s = s.substring(3);
    s = s.replaceAll('I', '1').replaceAll('L', '1').replaceAll('O', '0');
    if (!RegExp(r'^[0-9A-Z]+$').hasMatch(s)) return null;
    return s;
  }

  static String _format(String b32) {
    final groups = <String>[];
    for (var i = 0; i < b32.length; i += 6) {
      final end = (i + 6 > b32.length) ? b32.length : i + 6;
      groups.add(b32.substring(i, end));
    }
    return 'JSH-${groups.join('-')}';
  }

  static String _base32Encode(List<int> bytes) {
    var bits = 0;
    var value = 0;
    final out = StringBuffer();
    for (final b in bytes) {
      value = (value << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(kBase32Alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      out.write(kBase32Alphabet[(value << (5 - bits)) & 31]);
    }
    return out.toString();
  }

  static List<int>? _base32Decode(String s) {
    if (s.length != 36) return null;
    final bits = BytesBuilder();
    var value = 0;
    var count = 0;
    for (var i = 0; i < s.length; i++) {
      final idx = kBase32Alphabet.indexOf(s[i]);
      if (idx < 0) return null;
      value = (value << 5) | idx;
      count += 5;
      if (count >= 8) {
        bits.addByte((value >> (count - 8)) & 0xFF);
        count -= 8;
      }
    }
    return bits.toBytes();
  }
}
