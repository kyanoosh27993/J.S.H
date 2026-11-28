/// دروازه اعتبارسنجی کد فعال‌سازی برای اتصال گوشی به رایانه — بند ۴ — فاز ۶ب
///
/// سناریو بند ۴: نسخه اندروید (APK) برنامه، ابزار مستقلی نیست و فقط در
/// همراهی با رایانه فروشگاه (که کد فعال‌سازی آن معتبر است) کار می‌کند.
/// هر بار که گوشی به رایانه وصل می‌شود — از جمله هر ارسال عکس روی وای‌فای —
/// کد فعال‌سازی رایانه دوباره بررسی می‌شود؛ اگر اعتبار رایانه تمام شده یا
/// کد دستکاری شده باشد، ارسال عکس با خطای ۴۰۳ رد می‌شود و هیچ داده‌ای ذخیره
/// نمی‌شود.
///
/// چرا اینجا «اعتبارسنجی کامل دستگاهی» ممکن نیست؟
/// `ActivationEngine.verify` (یا همان `ActivationCodec.verify`) برای مقایسه
/// دستگاه، شناسه رایانه (`deviceId`) را لازم دارد؛ اما گوشی شناسه رایانه را
/// نمی‌داند. در عوض ساختار کد به ما کمک می‌کند:
///
///   payload = magic + version + expiryDays(3) + maxReinstalls + deviceHash(8)
///   code    = base32(payload + HMAC-SHA256(payload, key)[0..8])
///
/// `ActivationCodec.verify` ابتدا امضای HMAC را می‌سنجد و بعد تطبیق دستگاه را:
/// اگر کد را با یک شناسه «اکتشافی» بررسی کنیم:
///   • نتیجه `tampered` → امضای HMAC درست نیست → کد جعلی/دستکاری‌شده (رد)
///   • نتیجه `wrongDevice` → امضای HMAC معتبر است؛ فقط دستگاه فرق دارد →
///     برای گوشی طبیعی است، ادامه با بررسی تاریخ اعتبار جاسازی‌شده
///   • نتیجه `badFormat`/`wrongVersion` → کد اصلاً از جنس کد فعال‌سازی نیست (رد)
///
/// بنابراین اعتبارسنجی گوشی «صادقانه» است و هیچ چیز جعل نمی‌شود:
///   ۱) کد باید واقعاً با کلید HMAC برنامه امضا شده باشد (خودکاوری امضا)
///   ۲) تاریخ اعتبار جاسازی‌شده در payload باید از امروز نگذشته باشد
///   ۳) اگر شناسه دستگاه در دسترس باشد، تطبیق دستگاه هم کامل بررسی می‌شود
library;

import 'package:activation_core/activation_core.dart';

class LicenseGateService {
  LicenseGateService._();

  /// شناسه اکتشافی برای خودکاوری امضای HMAC —
  /// احتمال برابری هش آن با هش دستگاه داخل کد عملاً صفر است؛ اگر هم برابر
  /// شود، verify همه بررسی‌ها را کامل انجام داده و نتیجه ok همان معتبر است.
  static const String _probeDeviceId = '__jsh_license_gate_probe__';

  /// اعتبارسنجی کد فعال‌سازی رایانه — بدون دانستن شناسه رایانه.
  ///
  /// [code]: کد خام از هدر X-JSH-License (مثل JSH-XXXXXX-...)
  /// [deviceId]: اگر caller شناسه رایانه را بداند (فعلاً نداند)، تطبیق
  /// دستگاه هم انجام می‌شود؛ کد مال دستگاه دیگر → false.
  ///
  /// خروجی true یعنی کد دست‌نخورده و داخل بازه اعتبار است.
  static Future<bool> validate(String? code, {String? deviceId}) async {
    if (code == null || code.trim().isEmpty) return false;
    final today = DateTime.now();
    final r = ActivationCodec.verify(
        code: code, deviceId: deviceId ?? _probeDeviceId, today: today);
    switch (r.check) {
      case ActivationCheck.ok:
        // امضا + دستگاه + تاریخ همه درست — فقط در مسیر deviceId واقعی رخ می‌دهد
        return true;
      case ActivationCheck.expired:
        // کد معتبر است اما اعتبارش تمام شده (فقط در مسیر deviceId واقعی)
        return false;
      case ActivationCheck.tampered:
      case ActivationCheck.badFormat:
      case ActivationCheck.wrongVersion:
        // امضای HMAC خراب است یا اصلاً کد فعال‌سازی ما نیست
        return false;
      case ActivationCheck.wrongDevice:
        // امضای HMAC معتبر؛ اگر deviceId واقعی داده شده بود یعنی کد مال
        // دستگاه دیگری است. در مسیر گوشی (deviceId اکتشافی) ادامه با بررسی تاریخ.
        if (deviceId != null) return false;
        return _expiryStillValid(code, today);
    }
  }

  /// استخراج تاریخ اعتبار از payload و مقایسه با امروز —
  /// دقیقاً همان منطق `ActivationCodec.verify` برای تاریخ
  /// (`_epochDays(today) > expDays` یعنی منقضی) با ثابت‌های عمومی بسته.
  static bool _expiryStillValid(String code, DateTime today) {
    final normalized = _normalize(code);
    if (normalized == null || normalized.length != 36) return false;
    final bytes = _base32Decode(normalized);
    if (bytes == null || bytes.length != kTotalLen) return false;
    // verify پیش از wrongDevice مقدار magic/version را چک کرده؛ برای
    // مطمئن بودن دوباره بررسی می‌شود
    if (bytes[0] != kMagicByte || bytes[1] != kVersionByte) return false;
    final expDays = (bytes[2] << 16) | (bytes[3] << 8) | bytes[4];
    final todayDays =
        today.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;
    return todayDays <= expDays;
  }

  /// نسخه محلیِ نرمال‌سازی کد — آینه `ActivationCodec._normalize` است
  /// (خصوصی است و از بیرون در دسترس نیست). اگر روزی منطق نرمال‌سازی در
  /// activation_core تغییر کند، این تابع باید با همان تغییر هم‌گام شود؛
  /// در بدترین حالت ناهم‌سنجی، کد رد می‌شود (خطا در جهت امن).
  static String? _normalize(String raw) {
    var s = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-–—]'), '');
    if (s.startsWith('JSH')) s = s.substring(3);
    s = s.replaceAll('I', '1').replaceAll('L', '1').replaceAll('O', '0');
    if (!RegExp(r'^[0-9A-Z]+$').hasMatch(s)) return null;
    return s;
  }

  /// نسخه محلیِ رمزگشایی base32 — آینه `ActivationCodec._base32Decode`
  /// با الفبای عمومی `kBase32Alphabet`. فقط طول ۳۶ (payload+HMAC) می‌پذیرد.
  static List<int>? _base32Decode(String s) {
    if (s.length != 36) return null;
    final out = <int>[];
    var value = 0;
    var count = 0;
    for (var i = 0; i < s.length; i++) {
      final idx = kBase32Alphabet.indexOf(s[i]);
      if (idx < 0) return null;
      value = (value << 5) | idx;
      count += 5;
      if (count >= 8) {
        out.add((value >> (count - 8)) & 0xFF);
        count -= 8;
      }
    }
    return out;
  }
}
