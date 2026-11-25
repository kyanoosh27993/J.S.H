/// کنترلر نشست برنامه — هماهنگی لایسنس، گزارش نصب، حلقه ایمیل و یادآوری
library;

import 'dart:async';

import '../constants.dart';
import '../models.dart';
import '../repos.dart';
import 'email_service.dart';
import 'install_report_service.dart';
import 'license_service.dart';
import 'backup_service.dart';
import 'reminder_service.dart';
import 'supervisor_service.dart';

class AppSession {
  AppSession._();
  static final AppSession I = AppSession._();

  LicenseState license = LicenseState();
  SmtpConfig smtp = SmtpConfig();
  bool locked = false;
  String lockReason = '';
  Timer? _emailTimer;

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

    // ۲) قفل نصب چهارم (F-09)
    try {
      await LicenseService.guard(count);
    } on LicenseLockedException catch (e) {
      locked = true;
      lockReason = LicenseService.lockMessage(e.installCount);
      return;
    }

    // ۳) تنظیمات SMTP و فروشگاه + پاک‌سازی بک‌آپ‌های اتوماتیک قدیمی (قاعده ۹)
    smtp = SmtpConfig.fromJson(await SettingsRepo.all());
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

  /// شروع حلقه تخلیه صف ایمیل — تا وقتی صف خالی است هر ۳۰ ثانیه
  void startEmailLoop() {
    _emailTimer?.cancel();
    _emailTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await EmailService.drainQueue(smtp);
        final sent = await SettingsRepo.get('install_report_sent') == '1';
        if (!license.reportSent && !(await EmailQueueRepo.hasPending())) {
          // صف خالی شد یعنی گزارش نصب ارسال شده
          license.reportStatus = 'sent';
          license.reportSentAt = DateTime.now().toIso8601String();
          await LicenseRepo.save(license);
          await LicenseIntegrity.write();
          if (!sent) await SettingsRepo.set('install_report_sent', '1');
        }
      } catch (_) {}
    });
    // تلاش فوری در شروع
    () async {
      try {
        await EmailService.drainQueue(smtp);
        if (!license.reportSent && !(await EmailQueueRepo.hasPending())) {
          license.reportStatus = 'sent';
          license.reportSentAt = DateTime.now().toIso8601String();
          await LicenseRepo.save(license);
          await LicenseIntegrity.write();
          await SettingsRepo.set('install_report_sent', '1');
        }
      } catch (_) {}
    }();
  }

  void stopEmailLoop() {
    _emailTimer?.cancel();
    _emailTimer = null;
  }

  /// ذخیره اطلاعات فروشگاه + SMTP + یادآوری از ویزارد/تنظیمات
  Future<void> saveShopAndPrefs({
    required Map<String, String> shop,
    required SmtpConfig smtpCfg,
    required int leadDays,
    required int hour,
  }) async {
    for (final e in shop.entries) {
      await SettingsRepo.set(e.key, e.value);
    }
    final j = smtpCfg.toJson();
    for (final e in j.entries) {
      await SettingsRepo.set('smtp_${e.key}', e.value);
    }
    await SettingsRepo.set('reminder_lead_days', '$leadDays');
    await SettingsRepo.set('reminder_hour', '$hour');
    smtp = smtpCfg;
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
