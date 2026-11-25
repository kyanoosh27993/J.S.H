/// ویزارد راه‌اندازی اول (N-01 + N-03):
/// ۱) مجوز ارسال گزارش به سازنده  ۲) ایمیل معتبر کاربر + SMTP
/// ۳) اطلاعات فروشگاه (پیش‌پر از اطلاعات سازنده تا اصلاح)  ۴) تنظیمات یادآوری
library;

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../core/constants.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/email_service.dart';
import '../../core/services/install_report_service.dart';
import '../../core/services/license_service.dart';
import '../../core/utils.dart';

class OnboardingWizard extends StatefulWidget {
  final AppSession session;
  final VoidCallback onDone;
  const OnboardingWizard({super.key, required this.session, required this.onDone});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int step = 0;
  bool consent = false;
  bool sending = false;
  String sendError = '';

  final buyerName = TextEditingController();
  final userEmail = TextEditingController();
  final smtpUser = TextEditingController();
  final smtpPass = TextEditingController();
  final shopName = TextEditingController();
  final shopAddress = TextEditingController();
  final shopPhone = TextEditingController();
  final shopEmail = TextEditingController();
  int leadDays = ReminderPrefs.defaultLeadDays;
  int reminderHour = ReminderPrefs.defaultHour;

  final signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    final d = AppSession.shopDefaults();
    shopName.text = d['name'] ?? '';
    shopAddress.text = d['address'] ?? '';
    shopPhone.text = d['phone'] ?? '';
    shopEmail.text = d['email'] ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      buyerName, userEmail, smtpUser, smtpPass, shopName, shopAddress, shopPhone, shopEmail,
    ]) {
      c.dispose();
    }
    signatureController.dispose();
    super.dispose();
  }

  bool get canNext {
    switch (step) {
      case 0:
        return consent;
      case 1:
        return isValidEmail(userEmail.text.trim()) &&
            isValidEmail(smtpUser.text.trim()) &&
            smtpPass.text.isNotEmpty;
      case 2:
        return shopName.text.trim().isNotEmpty &&
            shopPhone.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  Future<void> _finish() async {
    setState(() {
      sending = true;
      sendError = '';
    });
    try {
      final s = widget.session;
      // ۱) ثبت رضایت و لایسنس
      s.license.consentedAt = DateTime.now().toIso8601String();
      s.license.userEmail = userEmail.text.trim();
      s.license.buyerName = buyerName.text.trim();
      s.license.hardwareReport = await InstallReportService.collectHardware();
      await LicenseRepo.save(s.license);

      // ۲) افزایش شمارنده نصب در مکان‌های مستقل (اولین فعال‌سازی این دستگاه)
      final fp = await LicenseService.fingerprint();
      await LicenseService.writeInstallCount(s.license.installCount, fp);

      // ۳) اطلاعات فروشگاه + تنظیمات یادآوری (N-01)
      await s.saveShopAndPrefs(
        shop: {
          'name': shopName.text.trim(),
          'address': shopAddress.text.trim(),
          'phone': shopPhone.text.trim(),
          'email': shopEmail.text.trim(),
        },
        smtpCfg: SmtpConfig.gmail(smtpUser.text.trim(), smtpPass.text.trim()),
        leadDays: leadDays,
        hour: reminderHour,
      );

      // ۴) صف گزارش نصب به شرکت سازنده (الزامی — N-03)
      await InstallReportService.enqueueReport(
        buyerName: s.license.buyerName,
        userEmail: s.license.userEmail,
        installCount: s.license.installCount,
        hardwareReport: s.license.hardwareReport,
      );
      await EmailService.drainQueue(s.smtp);

      if (mounted) {
        widget.onDone();
      }
    } catch (e) {
      setState(() => sendError = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('راه‌اندازی اول برنامه — ${AppInfo.appName}')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ستون گام‌ها
              SizedBox(
                width: 230,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stepTile(0, 'مجوز ارسال گزارش به سازنده'),
                    _stepTile(1, 'ایمیل و حساب ارسال شما'),
                    _stepTile(2, 'اطلاعات فروشگاه'),
                    _stepTile(3, 'تنظیمات یادآوری و امضا'),
                    const Spacer(),
                    Text('اثر انگشت این دستگاه:\n${InstallReportService.shortHash(widget.session.license.fingerprint)}',
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    const SizedBox(height: 6),
                    Text(
                        'نصب: ${toPersianDigits('${widget.session.license.installCount}')} از ${toPersianDigits('${AppInfo.maxInstalls}')}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const VerticalDivider(),
              Expanded(
                child: sending
                    ? const Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('در حال ثبت و ارسال گزارش فعال‌سازی به شرکت سازنده...'),
                        ],
                      ))
                    : _body(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepTile(int i, String label) {
    final active = step == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: active ? Theme.of(context).colorScheme.primaryContainer : null,
        child: ListTile(
          dense: true,
          leading: CircleAvatar(child: Text(toPersianDigits('${i + 1}'))),
          title: Text(label, style: const TextStyle(fontSize: 13)),
          onTap: i < step ? () => setState(() => step = i) : null,
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (step) {
      case 0:
        return _consentPage();
      case 1:
        return _emailPage();
      case 2:
        return _shopPage();
      case 3:
        return _reminderPage();
      default:
        return const SizedBox();
    }
  }

  Widget _consentPage() {
    return ListView(
      children: [
        const Text(
          'مجوز اتصال و ارسال گزارش فعال‌سازی',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'پس از نصب، برنامه یک گزارش فعال‌سازی برای شرکت سازنده ارسال می‌کند شامل:\n'
          '• نام خریدار و ایمیل ثبت‌شده\n'
          '• تاریخ و ساعت نصب\n'
          '• مشخصات دستگاه (نام رایانه، ویندوز، پردازنده، حافظه)\n'
          '• شماره نصب فعلی و تعداد نصب باقیمانده مجاز\n\n'
          'اگر اینترنت نداشته باشید، گزارش در صف می‌ماند و در اولین برقراری اینترنت ارسال می‌شود.\n'
          'تا ارسال موفق این گزارش، برنامه راه‌اندازی نمی‌شود. این شرط بخشی از لایسنس تجاری است.',
          style: TextStyle(fontSize: 13.5, height: 1.9),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: consent,
          onChanged: (v) => setState(() => consent = v ?? false),
          title: const Text(
            'می‌پذیرم که برنامه هنگام اتصال به اینترنت، گزارش فعال‌سازی را برای شرکت سازنده ارسال کند.',
            style: TextStyle(fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 16),
        _navRow(),
      ],
    );
  }

  Widget _emailPage() {
    return ListView(
      children: [
        const Text('ایمیل خریدار و حساب ارسال', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _field(buyerName, 'نام خریدار', hint: 'مثال: علی محمدی'),
        _field(userEmail, 'ایمیل شما (باید واقعی و معتبر باشد)'),
        const SizedBox(height: 14),
        const Text('حساب ارسال ایمیل (پیش‌فرض جیمیل — رمز برنامه ۱۶ رقمی گوگل)',
            style: TextStyle(fontSize: 12.5, color: Colors.blueGrey)),
        const SizedBox(height: 6),
        _field(smtpUser, 'ایمیل ارسال (Gmail)', hint: 'example@gmail.com'),
        _field(smtpPass, 'رمز برنامه (App Password)', obscure: true),
        const SizedBox(height: 16),
        _navRow(),
      ],
    );
  }

  Widget _shopPage() {
    return ListView(
      children: [
        const Text('اطلاعات فروشگاه (این اطلاعات در سربرگ رسیدها استفاده می‌شود)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('مقدار فعلی از اطلاعات شرکت سازنده است؛ فروشگاه خود را ثبت کنید.',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
        _field(shopName, 'نام فروشگاه'),
        _field(shopAddress, 'آدرس'),
        _field(shopPhone, 'تلفن'),
        _field(shopEmail, 'ایمیل فروشگاه (رسید سفارش‌ها به این آدرس ارسال می‌شود)'),
        const SizedBox(height: 16),
        _navRow(),
      ],
    );
  }

  Widget _reminderPage() {
    return ListView(
      children: [
        const Text('تنظیمات یادآوری و امضای فعال‌سازی', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('مدت یادآوری قبل از موعد تحویل:', style: TextStyle(fontSize: 13.5)),
        Wrap(
          spacing: 10,
          children: [
            for (final d in ReminderPrefs.allowedLeadDays)
              ChoiceChip(
                label: Text('${toPersianDigits('$d')} روز قبل'),
                selected: leadDays == d,
                onSelected: (_) => setState(() => leadDays = d),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('ساعت یادآوری روزانه:', style: TextStyle(fontSize: 13.5)),
        Slider(
          value: reminderHour.toDouble(),
          min: 0,
          max: 23,
          divisions: 23,
          label: toPersianDigits('$reminderHour:00'),
          onChanged: (v) => setState(() => reminderHour = v.round()),
        ),
        Center(child: Text('یادآوری هر روز ساعت ${toPersianDigits('$reminderHour:00')} نمایش داده می‌شود',
            style: const TextStyle(fontSize: 12.5))),
        const SizedBox(height: 12),
        const Text('امضای فعال‌سازی خریدار (دلخواه):', style: TextStyle(fontSize: 13.5)),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
          height: 120,
          child: Signature(controller: signatureController),
        ),
        const SizedBox(height: 14),
        _navRow(finalStep: true),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _navRow({bool finalStep = false}) {
    return Row(
      children: [
        if (step > 0)
          TextButton(
            onPressed: () => setState(() => step--),
            child: const Text('قبلی'),
          ),
        const Spacer(),
        FilledButton(
          onPressed: canNext
              ? () {
                  if (finalStep) {
                    _finish();
                  } else {
                    setState(() => step++);
                  }
                }
              : null,
          child: Text(finalStep ? 'ثبت نهایی و ارسال گزارش' : 'بعدی'),
        ),
      ],
    );
  }
}
