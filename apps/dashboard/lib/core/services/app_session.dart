/// کنترلر نشست برنامه — هماهنگی لایسنس، فعال‌سازی، گزارش نصب و یادآوری
library;

import '../constants.dart';
import '../models.dart';
import '../repos.dart';
import 'activation_service.dart';
import 'auth_service.dart';
import 'install_report_service.dart';
import 'license_service.dart';
import 'backup_service.dart';
import 'reminder_service.dart';
import 'supervisor_service.dart';

class AppSession {
  AppSession._();
  static final AppSession I = AppSession._();

  LicenseState license = LicenseState();
  bool locked = false;
  String lockReason = '';

  /// وضعیت فعال‌سازی — پس از هر init تازه می‌شود (فاز ۱)
  ActivationStatus activationStatus = ActivationStatus.notActivated;

  /// کاربر جاری — فاز ۲ (بند ۸). null یعنی هیچ‌کس وارد نشده
  AuthUser? currentUser;

  /// آیا کاربر جاری دسترسی داده‌شده را دارد؟
  bool can(String permKey) => currentUser?.can(permKey) ?? false;

  /// ورود کاربر — خروجی پیام خطا یا null در موفقیت
  Future<String?> loginWith(String username, String password) async {
    final (u, err) = await AuthService.login(username, password);
    if (err.isNotEmpty || u == null) return err;
    currentUser = u;
    return null;
  }

  /// خروج کاربر جاری
  Future<void> logout() async {
    final u = currentUser;
    currentUser = null;
    if (u != null) await AuthService.logout(u);
  }

  Future<void> init() async {
    // ۱) لایسنس و شمارنده نصب
    final fp = await LicenseService.fingerprint();
    final fileCount = await LicenseService.readInstallCount();
    final state = await LicenseRepo.load();
    // بیشینه سه مکان: فایل پنهان، رجیستری، پایگاه‌داده
    var count = state.installCount;
    if (fileCount > count) count = fileCount;
    // ضد دستکاری: شمارنده هرگز زیر آینه خارجی نمی‌آید (قاعده ۱۲)
    final mirror =
        int.tryParse(await SettingsRepo.get('install_count_mirror')) ?? 0;
    if (mirror > count) count = mirror;
    // اگر اثر انگشت پایگاه‌داده با این دستگاه فرق داشت یعنی کپی شد — همان شمارنده حفظ می‌شود
    state.installCount = count;
    state.fingerprint = fp;
    if (state.firstRunAt.isEmpty) {
      state.firstRunAt = DateTime.now().toIso8601String();
    }
    await LicenseRepo.save(state);
    await LicenseIntegrity.mirrorCount(count);
    license = state;

    // ۱-ب) بررسی دستکاری لایسنس (قاعده ۱۲)
    final integrity = await LicenseIntegrity.verify();
    if (integrity != LicenseIntegrityResult.ok) {
      locked = true;
      lockReason = 'تشخیص دستکاری در اطلاعات لایسنس.\n'
          'رکورد لایسنس با امضای امنیتی (HMAC) محافظت می‌شود و ویرایش دستی آن مجاز نیست.\n'
          'برای رفع مشکل با پشتیبانی تماس بگیرید:\n'
          '${VendorInfo.companyName} — ${VendorInfo.phoneDisplay} — ${VendorInfo.email}';
      return;
    }
    await LicenseIntegrity.write();

    // ۱-پ) نگهبان تاریخ سیستم — ضد عقب‌بردن تاریخ (بند ۳ درخواست صاحب پروژه)
    //
    // بازبینی ضد هک فاز ۸ (بند ۳):
    //   • lastSeen از سه مکان مستقل خوانده و بیشینه گرفته می‌شود (رکورد لایسنس،
    //     آینه settings، فایل پنهان) → پاک‌کردن فقط یکی کافی نیست.
    //   • آستانه تحمل ۳۰ ساعت است (زیرا مقایسه روی نیمه‌شب تاریخ انجام می‌شود،
    //     عملاً فقط یک روز اختلاف منطقه زمانی تحمل می‌شود؛ عقب‌بردن ۲ روز = قفل).
    //   • تشخیص عقب‌بردن → قفل کامل + ثبت «date_rollback» در audit_log تا ردپای
    //     دستکاری در گزارش سازنده بماند.
    try {
      await ActivationService.clockGuard(state);
      await LicenseRepo.save(state);
    } on ClockTamperedException catch (e) {
      // فاز ۸ — بند ۳: ردپای حسابرسی برای عقب‌بردن تاریخ سیستم
      await AuditRepo.log(
          'date_rollback',
          'تاریخ سیستم عقب‌تر از آخرین اجرا — lastSeen: ${e.lastSeen} / '
          'اکنون: ${e.now}');
      locked = true;
      lockReason = 'تغییر تاریخ سیستم تشخیص داده شد.\n'
          'برنامه بر پایه تاریخ سیستم کار می‌کند و عقب‌بردن آن، اعتبار کد فعال‌سازی را '
          'طولانی نمی‌کند و اجازه اجرا نمی‌دهد.\n'
          'لطفاً تاریخ و ساعت رایانه را روی زمان واقعی تنظیم کنید.\n'
          'اگر تاریخ سیستم درست است و این پیام دیده می‌شود، با پشتیبانی تماس بگیرید:\n'
          '${VendorInfo.companyName} — ${VendorInfo.phoneDisplay} — ${VendorInfo.email}';
      return;
    }

    // ۱-ت) وضعیت فعال‌سازی با کد (فاز ۱)
    try {
      activationStatus = await ActivationService.statusOf(state);
    } catch (_) {
      activationStatus = state.activated
          ? ActivationStatus.expired
          : ActivationStatus.notActivated;
    }
    if (activationStatus == ActivationStatus.expired) {
      locked = true;
      lockReason = ActivationService.expiryLockMessage();
      return;
    }

    // ۲) قفل نصب چهارم (F-09)
    try {
      await LicenseService.guard(count);
    } on LicenseLockedException catch (e) {
      locked = true;
      lockReason = LicenseService.lockMessage(e.installCount);
      return;
    }

    // ۳) پاک‌سازی بک‌آپ‌های اتوماتیک قدیمی (قاعده ۹)
    await BackupService.cleanupAutoBackups();
  }

  GateState gateState() {
    final firstRun = license.firstRunAt;
    return InstallReportService.evaluateGate(
      consented: license.consentedAt.isNotEmpty,
      userEmail: license.userEmail,
      reportSent: license.reportSent,
      firstRunAt: firstRun,
      pendingReportAttempts: 0,
    );
  }

  /// علامت‌گذاری ثبت گزارش نصب (ذخیره محلی) — دروازه راه‌اندازی باز می‌شود
  Future<void> markReportSent() async {
    license.reportStatus = 'sent';
    license.reportSentAt = DateTime.now().toIso8601String();
    await LicenseRepo.save(license);
    await LicenseIntegrity.write();
    await SettingsRepo.set('install_report_sent', '1');
  }

  /// فعال‌سازی با کد — از صفحه فعال‌سازی فراخوانده می‌شود
  /// خروجی: پیام خطا یا null در صورت موفقیت
  Future<String?> activateWithCode(String code) async {
    final err = await ActivationService.activate(license, code);
    if (err == null) {
      activationStatus = ActivationStatus.active;
    }
    return err;
  }

  /// ذخیره اطلاعات فروشگاه + تنظیمات یادآوری از ویزارد/تنظیمات
  Future<void> saveShopAndPrefs({
    required Map<String, String> shop,
    required int leadDays,
    required int hour,
  }) async {
    for (final e in shop.entries) {
      await SettingsRepo.set(e.key, e.value);
    }
    await SettingsRepo.set('reminder_lead_days', '$leadDays');
    await SettingsRepo.set('reminder_hour', '$hour');
    // حسابرسی (قاعده ۱۰): هم‌گام‌سازی یادآوری‌های در انتظار با تنظیم جدید
    try {
      await ReminderService.recomputePendingReminders(leadDays, hour);
    } catch (_) {}
  }

  /// مقدارهای پیش‌پر اطلاعات فروشگاه از اطلاعات شرکت سازنده (N-02، موقت تا اصلاح)
  static Map<String, String> shopDefaults() => {
        'name': VendorInfo.companyName,
        'address': VendorInfo.address,
        'phone': VendorInfo.supportPhone,
        'email': VendorInfo.email,
        'owner': '',
        'terms': 'اینجانب در صورت بروز هرگونه مشکل و خاموش شدن دستگاه خود '
            'نسبت به این فروشگاه هیچ‌گونه ادعایی ندارم.',
      };
}
