/// ابزار خط فرمان تولید و بررسی کد فعال‌سازی J.S.H — نسخه بدون رابط گرافیکی
///
/// کاربردها:
///   ۱) تولید کد برای خودکارسازی (اسکریپت/دسته‌ای) بدون باز کردن برنامه مولد:
///      dart run example/make_code.dart --device <شناسه ۳۲ کاراکتری> --expiry 1406/09/04
///   ۲) بررسی صحت یک کد روی دستگاه جاری یا شناسه دلخواه:
///      dart run example/make_code.dart --verify JSH-XXXX --device <شناسه>
///
/// تاریخ اعتبار هم شمسی (۱۴۰۶/۰۹/۰۴) و هم میلادی (2027-11-25) پذیرفته می‌شود.
/// تاریخ پایان اعتبار در کد، ساعت ۱۲ ظهر UTC همان روز ذخیره می‌شود (مطابق برنامه مولد گرافیکی).
///
/// این ابزار از همان ActivationCodec بسته استفاده می‌کند؛ یعنی خروجی آن دقیقاً
/// با خروجی برنامه جانبی apps/license_gen یکسان است.
library;

import 'dart:io';

import 'package:activation_core/activation_core.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;

void main(List<String> args) {
  String? device;
  String? expiryRaw;
  String? verifyCode;
  var reinstalls = 0;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        device = args[++i];
      case '--expiry':
        expiryRaw = args[++i];
      case '--reinstalls':
        reinstalls = int.tryParse(args[++i]) ?? 0;
      case '--verify':
        verifyCode = args[++i];
      case '-h':
      case '--help':
        _usage();
        return;
      default:
        stderr.writeln('آرگومان ناشناخته: ${args[i]}');
        _usage();
        exit(2);
    }
  }

  if (verifyCode != null) {
    if (device == null) {
      stderr.writeln('برای بررسی کد، --device هم لازم است.');
      exit(2);
    }
    _verify(verifyCode, _cleanDevice(device));
    return;
  }

  if (device == null || expiryRaw == null) {
    _usage();
    exit(2);
  }

  final expiry = _parseExpiry(expiryRaw);
  if (expiry == null) {
    stderr.writeln(
        'تاریخ اعتبار نامعتبر است. شمسی مثل 1406/09/04 یا میلادی مثل 2027-11-25 بدهید.');
    exit(2);
  }
  final dev = _cleanDevice(device);
  final err = _validateDevice(dev);
  if (err != null) {
    stderr.writeln(err);
    exit(2);
  }
  final code = ActivationCodec.generate(
    expiry: DateTime.utc(expiry.year, expiry.month, expiry.day, 12),
    deviceId: dev,
    maxReinstalls: reinstalls.clamp(0, 255),
  );
  final jd = j.Jalali.fromDateTime(expiry);
  stdout
    ..writeln('کد فعال‌سازی:')
    ..writeln(code)
    ..writeln('')
    ..writeln('پایان اعتبار (میلادی): ${expiry.year}-${_p2(expiry.month)}-${_p2(expiry.day)}')
    ..writeln('پایان اعتبار (شمسی): ${jd.year}/${_p2(jd.month)}/${_p2(jd.day)}')
    ..writeln('سقف نصب مجدد: ${reinstalls == 0 ? '۰ (پیش‌فرض برنامه — ۳ بار)' : reinstalls}')
    ..writeln('اثر کوتاه دستگاه: ${ActivationCodec.shortDeviceId(dev)}');
  // خودآزمایی: کد تازه‌ساخته باید روی همین شناسه درست باشد
  final check = ActivationCodec.verify(
      code: code, deviceId: dev, today: DateTime.now().toUtc());
  if (!check.ok) {
    stderr.writeln('خطا: کد ساخته‌شده خودآزمایی را نگذشت — $check');
    exit(3);
  }
}

void _verify(String code, String device) {
  final r = ActivationCodec.verify(
      code: code, deviceId: device, today: DateTime.now().toUtc());
  const names = {
    ActivationCheck.ok: 'معتبر',
    ActivationCheck.badFormat: 'قالب کد نادرست است',
    ActivationCheck.tampered: 'کد دستکاری شده است (امضا نامعتبر)',
    ActivationCheck.wrongDevice: 'کد مال دستگاه دیگری است',
    ActivationCheck.expired: 'اعتبار کد تمام شده است',
    ActivationCheck.wrongVersion: 'نسخه کد با این نسخه برنامه نمی‌خواند',
  };
  final expiry = r.expiry;
  stdout
    ..writeln('نتیجه بررسی: ${names[r.check]}')
    ..writeln(r.ok
        ? 'پایان اعتبار: ${expiry!.year}-${_p2(expiry.month)}-${_p2(expiry.day)} | سقف نصب مجدد: ${r.maxReinstalls == 0 ? 'پیش‌فرض' : r.maxReinstalls}'
        : '');
  exit(r.ok ? 0 : 1);
}

String _cleanDevice(String raw) => raw.replaceAll('-', '').trim().toLowerCase();

String? _validateDevice(String s) {
  if (s.length != 32) {
    return 'شناسه دستگاه باید ۳۲ کاراکتر باشد — همان که صفحه فعال‌سازی برنامه نشان می‌دهد.';
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(s)) {
    return 'شناسه دستگاه فقط رقم و حروف انگلیسی (hex) است.';
  }
  return null;
}

DateTime? _parseExpiry(String raw) {
  var s = raw.trim();
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(fa[i], en[i]);
  }
  s = s.replaceAll(RegExp(r'[-٫]'), '/');
  // میلادی ISO: 2027-11-25
  final iso = RegExp(r'^(\d{4})/(\d{2})/(\d{2})$').firstMatch(raw.trim());
  if (iso != null) {
    final y = int.parse(iso.group(1)!);
    if (y > 1700) {
      final m = int.parse(iso.group(2)!);
      final d = int.parse(iso.group(3)!);
      try {
        return DateTime(y, m, d);
      } catch (_) {
        return null;
      }
    }
  }
  // شمسی: 1406/09/04
  final parts = s.split('/');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  final d = int.tryParse(parts[2].trim());
  if (y == null || m == null || d == null) return null;
  try {
    return j.Jalali(y, m, d).toDateTime();
  } catch (_) {
    return null;
  }
}

String _p2(int v) => v.toString().padLeft(2, '0');

void _usage() {
  stdout
    ..writeln('مولد کد فعال‌سازی J.S.H — ابزار خط فرمان')
    ..writeln('')
    ..writeln('تولید کد:')
    ..writeln('  dart run example/make_code.dart --device <شناسه ۳۲ کاراکتری> '
        '--expiry <شمسی یا میلادی> [--reinstalls <۰تا۲۵۵>]')
    ..writeln('  مثال: dart run example/make_code.dart --device 8f3b1c2d4e5f6a7b8c9d0e1f2a3b4c5d '
        '--expiry 1406/09/04')
    ..writeln('  مثال: dart run example/make_code.dart --device 8f3b1c2d... --expiry 2027-11-25 --reinstalls 1')
    ..writeln('')
    ..writeln('بررسی کد:')
    ..writeln('  dart run example/make_code.dart --verify <کد> --device <شناسه>');
}
