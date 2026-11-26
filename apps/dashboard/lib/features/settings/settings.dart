/// تنظیمات (N-01) — اطلاعات فروشگاه و تنظیمات یادآوری
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
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
  int leadDays = ReminderPrefs.defaultLeadDays;
  int reminderHour = ReminderPrefs.defaultHour;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [shopName, shopAddress, shopPhone, shopEmail]) {
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
      leadDays: leadDays,
      hour: reminderHour,
    );
    setState(() => saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => saved = false);
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
            _f(shopEmail, 'ایمیل فروشگاه (در سربرگ رسیدها نمایش داده می‌شود)'),
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
