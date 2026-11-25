/// تنظیمات (N-01) — اطلاعات فروشگاه، حساب ایمیل، تنظیمات یادآوری + تست ارسال
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/email_service.dart';
import '../../core/utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final shopName = TextEditingController();
  final shopAddress = TextEditingController();
  final shopPhone = TextEditingController();
  final shopEmail = TextEditingController();
  final smtpUser = TextEditingController();
  final smtpPass = TextEditingController();
  int leadDays = ReminderPrefs.defaultLeadDays;
  int reminderHour = ReminderPrefs.defaultHour;
  bool saved = false;
  bool testing = false;
  String testResult = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [shopName, shopAddress, shopPhone, shopEmail, smtpUser, smtpPass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SettingsRepo.all();
    if (!mounted) return;
    setState(() {
      shopName.text = s['name'] ?? '';
      shopAddress.text = s['address'] ?? '';
      shopPhone.text = s['phone'] ?? '';
      shopEmail.text = s['email'] ?? '';
      smtpUser.text = s['smtp_username'] ?? '';
      smtpPass.text = s['smtp_password'] ?? '';
      leadDays = int.tryParse(s['reminder_lead_days'] ?? '') ?? ReminderPrefs.defaultLeadDays;
      reminderHour = int.tryParse(s['reminder_hour'] ?? '') ?? ReminderPrefs.defaultHour;
    });
  }

  Future<void> _save() async {
    await AppSession.I.saveShopAndPrefs(
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
    setState(() => saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => saved = false);
  }

  Future<void> _testEmail() async {
    setState(() {
      testing = true;
      testResult = '';
    });
    try {
      await EmailQueueRepo.enqueue(
        to: smtpUser.text.trim(),
        subject: 'ایمیل آزمایشی — ${AppInfo.appName}',
        body: 'اگر این ایمیل را دریافت کرده‌اید، تنظیمات ارسال درست است.',
      );
      final sent = await EmailService.drainQueue(AppSession.I.smtp);
      setState(() => testResult =
          sent > 0 ? 'ارسال موفق بود — ایمیل آزمایشی دریافت شد.' : 'ارسال انجام نشد — اتصال اینترنت یا رمز برنامه را بررسی کنید.');
    } catch (e) {
      setState(() => testResult = 'خطا: $e');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('تنظیمات برنامه', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text('اطلاعات فروشگاه (در سربرگ PDF رسیدها استفاده می‌شود)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _f(shopName, 'نام فروشگاه'),
            _f(shopAddress, 'آدرس'),
            _f(shopPhone, 'تلفن'),
            _f(shopEmail, 'ایمیل فروشگاه (مقصد رسید سفارش‌ها)'),
            const SizedBox(height: 16),
            const Text('حساب ارسال ایمیل (جیمیل + رمز برنامه ۱۶ رقمی گوگل)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _f(smtpUser, 'ایمیل ارسال'),
            _f(smtpPass, 'رمز برنامه', obscure: true),
            const SizedBox(height: 6),
            Row(children: [
              FilledButton.tonalIcon(
                onPressed: testing ? null : _testEmail,
                icon: testing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('تست ارسال ایمیل'),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(testResult, style: const TextStyle(fontSize: 12.5))),
            ]),
            const SizedBox(height: 16),
            const Text('تنظیمات یادآوری', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final d in ReminderPrefs.allowedLeadDays)
                  ChoiceChip(
                    label: Text('${toPersianDigits('$d')} روز قبل از موعد'),
                    selected: leadDays == d,
                    onSelected: (_) => setState(() => leadDays = d),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('ساعت یادآوری روزانه: ${toPersianDigits('$reminderHour:00')}'),
            Slider(
              value: reminderHour.toDouble(),
              min: 0,
              max: 23,
              divisions: 23,
              onChanged: (v) => setState(() => reminderHour = v.round()),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(saved ? 'ذخیره شد ✓' : 'ذخیره تنظیمات'),
            ),
            const Divider(height: 28),
            Text('پشتیبانی برنامه', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              '${VendorInfo.companyName}\n${VendorInfo.phoneDisplay}\n${VendorInfo.address}\nایمیل: ${VendorInfo.email}',
              style: TextStyle(fontSize: 13, height: 1.8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _f(TextEditingController c, String label, {bool obscure = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
