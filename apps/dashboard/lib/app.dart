/// ریشه برنامه — دروازه راه‌اندازی: قفل لایسنس → ویزارد اول → شل اصلی
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

import 'core/constants.dart';
import 'core/services/activation_service.dart';
import 'core/services/app_session.dart';
import 'core/services/backup_service.dart';
import 'core/services/install_report_service.dart';
import 'core/services/reminder_service.dart';
import 'features/activation/activation_page.dart';
import 'features/activation/pair_page.dart';
import 'features/onboarding/onboarding.dart';
import 'features/shell/shell.dart';
import 'features/users/login_page.dart';
import 'features/mobile_link/mobile_link_page.dart';
import 'core/theme/theme_config.dart';
import 'features/support/blocked.dart';

class JshDashboardApp extends StatefulWidget {
  final AppSession session;
  /// خطای راه‌اندازی اولیه (در صورت وجود) — به‌جای صفحه سیاه نمایش داده می‌شود
  final Object? bootError;
  const JshDashboardApp({super.key, required this.session, this.bootError});

  @override
  State<JshDashboardApp> createState() => _JshDashboardAppState();
}

class _JshDashboardAppState extends State<JshDashboardApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _initDesktopNotifications();
    // بک‌آپ اتوماتیک بی‌صدا هنگام خروج — قاعده ۹
    if (!widget.session.locked) {
      _lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          await BackupService.autoBackup();
          return AppExitResponse.exit;
        },
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _initDesktopNotifications() async {
    if (widget.session.locked) return;
    try {
      await localNotifier.setup(appName: AppInfo.projectId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // تم زنده — هر تغییر شخصی‌سازی بلافاصله در کل برنامه اعمال می‌شود
    return ValueListenableBuilder<ThemeConfig>(
      valueListenable: ThemeConfig.notifier,
      builder: (context, cfg, _) {
        final themeData = AppTheme.build(cfg);
        return MaterialApp(
          title: AppInfo.appName,
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa', 'IR'),
          theme: themeData,
          builder: (context, child) => AppThemeScope(
            notifier: ThemeConfig.notifier,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: _RootGate(session: widget.session, bootError: widget.bootError),
        );
      },
    );
  }

}

/// دروازه اصلی — هر بار اجرا از نو بررسی می‌شود (N-03 مطلق است)
class _RootGate extends StatefulWidget {
  final AppSession session;
  /// خطای راه‌اندازی اولیه — نمایش صریح به‌جای صفحه سیاه
  final Object? bootError;
  const _RootGate({required this.session, this.bootError});

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  Timer? _retry;
  int tick = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.session.locked) {
      _retry = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() => tick++);
      });
      _startReminders();
    }
  }

  Future<void> _startReminders() async {
    ReminderService.startPeriodicCheck((r) async {
      await localNotify('یادآوری تعمیرات', r.message);
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  /// روزهای باقیمانده اعتبار برای هشدار ۷ روز مانده (بند ۱۸) — null یعنی هشدار لازم نیست
  int? _expiryNoticeDays() {
    final s = widget.session;
    if (s.activationStatus != ActivationStatus.active) return null;
    final remaining = ActivationService.remainingDays(s.license);
    if (remaining <= 0 || remaining > 7) return null;
    return remaining;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    // ۰) خطای راه‌اندازی اولیه — نمایش صریح به‌جای صفحه سیاه
    if (widget.bootError != null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          child: BlockedPage(
            title: 'خطا در راه‌اندازی برنامه',
            message: 'برنامه نتوانست پایگاه‌داده محلی را باز کند:\n'
                '${widget.bootError}\n\n'
                'لطفاً از نصب کامل فایل نصبی مطمئن شوید و دوباره تلاش کنید. '
                'اگر مشکل ادامه داشت با پشتیبانی تماس بگیرید.',
            showRetry: true,
            onRetry: () async {
              try {
                await s.init();
              } catch (_) {}
              if (mounted) setState(() {});
            },
          ),
        ),
      );
    }
    // v0.12.4 — اندروید: روند جدید فعال‌سازی. گوشی مستقل فعال نمی‌شود؛
    // با جفت‌سازی به PC فعالِ در شبکه لوکال پورت 3000 راه‌اندازی می‌شود (بند ۴)
    if (!kIsWeb && Platform.isAndroid && !s.locked) {
      return PairGate(session: s, onDone: () => setState(() {}));
    }

    // ۱) قفل لایسنس (F-09): نصب چهارم → فقط پیام پشتیبانی
    if (s.locked) {
      return BlockedPage(
        title: 'نصب مجاز نیست — تماس با پشتیبانی',
        message: s.lockReason,
        showRetry: false,
      );
    }

    // v0.12.5 — دروازه گزارش نصب/ایمیل (N-03) کلاً حذف شد؛ فعال‌سازی فقط با کد
    // (بند ۴). فعال‌سازی با کد و سپس ورود کاربر (بند ۸):
    if (s.activationStatus == ActivationStatus.notActivated) {
      return ActivationPage(session: s, onActivated: () => setState(() {}));
    }
    if (s.currentUser == null) {
      return LoginPage(session: s, onLoggedIn: () => setState(() {}));
    }
    return MainShell(
      session: s,
      expiryNoticeDays: _expiryNoticeDays(),
      onLogout: () => setState(() {}),
    );
  }
}

/// اعلان دسکتاپ امن — خطاها برنامه را نمی‌بندند
Future<void> localNotify(String title, String body) async {
  try {
    final n = LocalNotification(title: title, body: body);
    await n.show();
  } catch (_) {}
}
