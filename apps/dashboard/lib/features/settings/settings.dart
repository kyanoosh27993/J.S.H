/// تنظیمات (N-01 + فاز ۴) — اطلاعات فروشگاه، یادآوری با عدد دلخواه (بند ۱)،
/// لوازم همراه قابل ویرایش (بند ۱۰)، تصاویر امضا/مهر/لوگو (بند ۶ و ۱۸)
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/shop_settings_service.dart';
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
  final leadDaysCtrl = TextEditingController();
  final preInvoiceStartCtrl = TextEditingController();
  final invoiceStartCtrl = TextEditingController();
  int reminderHour = ReminderPrefs.defaultHour;
  bool saved = false;
  // بند ۱ — نمایش اقرارنامه و پترن قفل در فرم پذیرش
  bool showTerms = true;
  bool showPattern = true;

  // لوازم همراه — قابل ویرایش (بند ۱۰)
  List<String> accessories = [];
  final newAccessory = TextEditingController();

  // تصاویر فروشگاه — امضا/مهر/لوگو (بند ۶)
  final Map<ShopImage, String> imagePaths = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      shopName,
      shopAddress,
      shopPhone,
      shopEmail,
      leadDaysCtrl,
      preInvoiceStartCtrl,
      invoiceStartCtrl,
      newAccessory
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SettingsRepo.all();
    final acc = await ShopSettingsService.loadAccessories();
    final paths = <ShopImage, String>{};
    for (final kind in ShopImage.values) {
      paths[kind] = await ShopSettingsService.pathOf(kind);
    }
    if (!mounted) return;
    setState(() {
      shopName.text = s['name'] ?? '';
      shopAddress.text = s['address'] ?? '';
      shopPhone.text = s['phone'] ?? '';
      shopEmail.text = s['email'] ?? '';
      leadDaysCtrl.text =
          s['reminder_lead_days'] ?? '${ReminderPrefs.defaultLeadDays}';
      preInvoiceStartCtrl.text = s['pre_invoice_start'] ?? '1';
      invoiceStartCtrl.text = s['invoice_start'] ?? '1';
      reminderHour =
          int.tryParse(s['reminder_hour'] ?? '') ?? ReminderPrefs.defaultHour;
      // بند ۱ — خواندن تنظیم نمایش اقرارنامه/پترن فرم پذیرش
      showTerms = (s['intake_show_terms'] ?? '1') != '0';
      showPattern = (s['intake_show_pattern'] ?? '1') != '0';
      accessories = acc;
      imagePaths.addAll(paths);
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
      leadDays: ReminderPrefs.clampLeadDays(
          int.tryParse(toEnglishDigits(leadDaysCtrl.text)) ??
              ReminderPrefs.defaultLeadDays),
      hour: reminderHour,
    );
    // بند ۱۲ — شروع شماره‌گذاری سند
    await SettingsRepo.set('pre_invoice_start',
        toEnglishDigits(preInvoiceStartCtrl.text.trim()).replaceAll(',', ''));
    await SettingsRepo.set('invoice_start',
        toEnglishDigits(invoiceStartCtrl.text.trim()).replaceAll(',', ''));
    await ShopSettingsService.saveAccessories(accessories);
    // بند ۱ — تنظیم نمایش اقرارنامه/پترن در فرم پذیرش
    await SettingsRepo.set('intake_show_terms', showTerms ? '1' : '0');
    await SettingsRepo.set('intake_show_pattern', showPattern ? '1' : '0');
    setState(() => saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => saved = false);
  }

  Future<void> _pickImage(ShopImage kind) async {
    final err = await ShopSettingsService.pickAndSave(kind);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final path = await ShopSettingsService.pathOf(kind);
    if (!mounted) return;
    setState(() => imagePaths[kind] = path);
  }

  Future<void> _clearImage(ShopImage kind) async {
    await ShopSettingsService.clear(kind);
    if (!mounted) return;
    setState(() => imagePaths[kind] = '');
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
            const Text('تنظیمات یادآوری',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // بند ۱ — عدد دلخواه، نه فقط ۲/۳/۷
            SizedBox(
              width: 220,
              child: TextField(
                controller: leadDaysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'یادآوری چند روز قبل از موعد؟ (۱ تا ۳۰)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // بند ۱ — سوییچ نمایش اقرارنامه و پترن قفل در فرم پذیرش
            SwitchListTile(
              value: showTerms,
              onChanged: (v) => setState(() => showTerms = v),
              title: const Text('نمایش اقرارنامه در فرم پذیرش (بند ۱)',
                  style: TextStyle(fontSize: 13)),
            ),
            SwitchListTile(
              value: showPattern,
              onChanged: (v) => setState(() => showPattern = v),
              title: const Text('نمایش پترن قفل دستگاه در فرم پذیرش (بند ۱)',
                  style: TextStyle(fontSize: 13)),
            ),
            Text('ساعت یادآوری روزانه: ${toPersianDigits('$reminderHour:00')}'),
            Slider(
              value: reminderHour.toDouble(),
              min: 0,
              max: 23,
              divisions: 23,
              onChanged: (v) => setState(() => reminderHour = v.round()),
            ),
            const SizedBox(height: 14),
            // بند ۱۰ — لوازم همراه قابل ویرایش
            const Text('لوازم همراه دستگاه (در فرم پذیرش نمایش داده می‌شود)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < accessories.length; i++)
                  InputChip(
                    label: Text(accessories[i]),
                    onDeleted: () =>
                        setState(() => accessories.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: newAccessory,
                    decoration: const InputDecoration(
                      labelText: 'مورد جدید (مثلاً شارژر)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addAccessory(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addAccessory,
                  icon: const Icon(Icons.add),
                  tooltip: 'افزودن',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // بند ۱۲ — شماره‌گذاری سند
            const Text(
                'شماره‌گذاری سند — شروع عدد افزاینده ۴ رقمی (سال+روز ثبت + شماره)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: preInvoiceStartCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'شروع پیش‌فاکتور (مثلاً 100)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: invoiceStartCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'شروع فاکتور (مثلاً 100)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // بند ۶ و ۱۸ — تصاویر امضا/مهر/لوگو
            const Text(
                'تصاویر فروشگاه (در فرم‌ها و فاکتورها به انتخاب کاربر استفاده می‌شود)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (final kind in ShopImage.values) _imageRow(kind),
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

  Future<void> _addAccessory() async {
    final v = newAccessory.text.trim();
    if (v.isEmpty || accessories.contains(v)) return;
    setState(() => accessories.add(v));
    newAccessory.clear();
    await ShopSettingsService.saveAccessories(accessories);
  }

  Widget _imageRow(ShopImage kind) {
    final path = imagePaths[kind] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(kind.labelFa,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              path.isEmpty ? 'ثبت نشده' : path.split('/').last,
              style: TextStyle(
                  fontSize: 12,
                  color: path.isEmpty
                      ? Colors.red
                      : Theme.of(context).colorScheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'انتخاب فایل تصویر',
            icon: const Icon(Icons.upload_file, size: 19),
            onPressed: () => _pickImage(kind),
          ),
          IconButton(
            tooltip: 'پاک کردن',
            icon: const Icon(Icons.delete_outline, size: 19),
            onPressed: path.isEmpty ? null : () => _clearImage(kind),
          ),
        ],
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
