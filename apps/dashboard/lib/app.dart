/// ریشه برنامه — دروازه راه‌اندازی: قفل لایسنس → ویزارد اول → بستن تا ارسال گزارش نصب
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

import 'core/constants.dart';
import 'core/services/app_session.dart';
import 'core/services/install_report_service.dart';
import 'core/services/reminder_service.dart';
import 'features/onboarding/onboarding.dart';
import 'features/shell/shell.dart';
import 'features/support/blocked.dart';

class JshDashboardApp extends StatefulWidget {
  final AppSession session;
  const JshDashboardApp({super.key, required this.session});

  @override
  State<JshDashboardApp> createState() => _JshDashboardAppState();
}

class _JshDashboardAppState extends State<JshDashboardApp> {
  @override
  void initState() {
    super.initState();
    _initDesktopNotifications();
  }

  Future<void> _initDesktopNotifications() async {
    if (widget.session.locked) return;
    try {
      await localNotifier.setup(appName: AppInfo.projectId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa', 'IR'),
      theme: _theme(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: _RootGate(session: widget.session),
    );
  }

  ThemeData _theme() {
    const seed = Color(0xFF1E3A5F);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      fontFamily: 'Vazirmatn',
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/// دروازه اصلی — هر بار اجرا از نو بررسی می‌شود (N-03 مطلق است)
class _RootGate extends StatefulWidget {
  final AppSession session;
  const _RootGate({required this.session});

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  Timer? _retry;
  int tick = 0;

  @override
  void initState() {
    super.initState();
    // حلقه ایمیل: تلاش برای ارسال گزارش نصب و رسیدها
    if (!widget.session.locked) {
      widget.session.startEmailLoop();
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

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    // ۱) قفل لایسنس (F-09): نصب چهارم → فقط پیام پشتیبانی
    if (s.locked) {
      return BlockedPage(
        title: 'نصب مجاز نیست — تماس با پشتیبانی',
        message: s.lockReason,
        showRetry: false,
      );
    }

    // ۲) دروازه گزارش نصب (N-03)
    switch (s.gateState()) {
      case GateState.waitingConsent:
        return OnboardingWizard(session: s, onDone: () => setState(() {}));
      case GateState.queueing:
        return BlockedPage(
          title: 'در انتظار ارسال گزارش فعال‌سازی به شرکت سازنده',
          message:
              'گزارش نصب شما در صف ارسال است. سیستم را به اینترنت متصل کنید تا گزارش '
              'به شرکت سازنده (${AppInfo.projectId}) ارسال شود.\n'
              'تا ارسال موفق این گزارش، برنامه راه‌اندازی نمی‌شود. '
              'برنامه هر لحظه به‌صورت خودکار تلاش می‌کند.',
          showRetry: true,
          onRetry: () => setState(() {}),
        );
      case GateState.deadlinePassed:
        return BlockedPage(
          title: 'اتصال اینترنت و ثبت ایمیل واقعی الزامی است',
          message:
              'بیش از ۳۰ روز از نصب گذشته است و گزارش فعال‌سازی به شرکت سازنده ارسال نشده است.\n'
              'لطفاً سیستم خود را به اینترنت متصل نمایید و ایمیل واقعی و خود را در تنظیمات ثبت کنید '
              'تا ۱۰۰ درصد ایمیل معتبر اخذ شود و سپس گزارش برای شرکت سازنده ارسال شود.\n'
              'تا انجام این کار، برنامه راه‌اندازی نخواهد شد.',
          showRetry: true,
          onRetry: () => setState(() {}),
        );
      case GateState.ok:
        return MainShell(session: s);
    }
  }
}

/// اعلان دسکتاپ امن — خطاها برنامه را نمی‌بندند
Future<void> localNotify(String title, String body) async {
  try {
    final n = LocalNotification(title: title, body: body);
    await n.show();
  } catch (_) {}
}
