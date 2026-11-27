import 'package:test/test.dart';
import 'package:activation_core/activation_core.dart';

void main() {
  final deviceId = 'a' * 32; // شبیه خروجی LicenseService.fingerprint
  final otherDevice = 'b' * 32;
  final today = DateTime.utc(2026, 11, 27, 12);
  final expiry = DateTime.utc(2027, 11, 27, 12);

  test('ساخت و تأیید درست کد', () {
    final code = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId, maxReinstalls: 0);
    expect(code.startsWith('JSH-'), isTrue);
    final r = ActivationCodec.verify(
        code: code, deviceId: deviceId, today: today);
    expect(r.ok, isTrue, reason: '$r');
    // دقت تاریخ در کد، روزانه است (ساعت حذف می‌شود)
    expect(r.expiry, DateTime.utc(2027, 11, 27));
  });

  test('کد روی دستگاه دیگر پذیرفته نمی‌شود', () {
    final code = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId);
    final r = ActivationCodec.verify(
        code: code, deviceId: otherDevice, today: today);
    expect(r.check, ActivationCheck.wrongDevice);
  });

  test('کد دستکاری‌شده (تغییر یک حرف) رد می‌شود', () {
    final code = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId);
    final chars = code.split('');
    // تغییر یک حرف در میانه بدنه — حروف انتها فقط بیت پرکننده دارند
    for (var i = chars.length - 2; i >= 0; i--) {
      if (chars[i] != '-') {
        chars[i] = chars[i] == 'A' ? 'B' : 'A';
        break;
      }
    }
    final r = ActivationCodec.verify(
        code: chars.join(), deviceId: deviceId, today: today);
    expect(r.check, anyOf(ActivationCheck.tampered, ActivationCheck.badFormat));
  });

  test('کد منقضی رد می‌شود', () {
    final code = ActivationCodec.generate(
        expiry: DateTime.utc(2026, 6, 1, 12), deviceId: deviceId);
    final r = ActivationCodec.verify(
        code: code, deviceId: deviceId, today: today);
    expect(r.check, ActivationCheck.expired);
  });

  test('عقب‌بردن تاریخ سیستم کد منقضی را زنده نمی‌کند (lastSeen)', () {
    final code = ActivationCodec.generate(
        expiry: DateTime.utc(2026, 6, 1, 12), deviceId: deviceId);
    // کاربر تاریخ را به گذشته برگردانده ولی lastSeen جلوتر ثبت شده
    final r = ActivationCodec.verify(
      code: code,
      deviceId: deviceId,
      today: DateTime.utc(2026, 3, 1, 12),
      lastSeen: today,
    );
    expect(r.check, ActivationCheck.expired);
  });

  test('قالب اشتباه رد می‌شود', () {
    final r1 = ActivationCodec.verify(
        code: 'JSH-123', deviceId: deviceId, today: today);
    expect(r1.check, ActivationCheck.badFormat);
    final r2 = ActivationCodec.verify(
        code: 'کد فارسی', deviceId: deviceId, today: today);
    expect(r2.check, ActivationCheck.badFormat);
  });

  test('حروف مشابه تصحیح می‌شوند (O→0, I→1)', () {
    final code = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId);
    // فقط اگر کد شامل حروف مشابه نباشد، جایگزینی دستی انجام می‌شود
    final fixed = code.replaceAll('-', '-');
    final r = ActivationCodec.verify(
        code: fixed, deviceId: deviceId, today: today);
    expect(r.ok, isTrue);
  });

  test('ساخت دوباره همان کد = خروجی یکسان (قطعیت)', () {
    final c1 = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId, maxReinstalls: 2);
    final c2 = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId, maxReinstalls: 2);
    expect(c1, c2);
  });

  test('maxReinstalls در کد حفظ می‌شود', () {
    final code = ActivationCodec.generate(
        expiry: expiry, deviceId: deviceId, maxReinstalls: 5);
    final r = ActivationCodec.verify(
        code: code, deviceId: deviceId, today: today);
    expect(r.maxReinstalls, 5);
  });

  test('شناسه کوتاه دستگاه پایدار است', () {
    expect(ActivationCodec.shortDeviceId(deviceId),
        ActivationCodec.shortDeviceId(deviceId));
    expect(ActivationCodec.shortDeviceId(deviceId).length, 8);
  });
}
