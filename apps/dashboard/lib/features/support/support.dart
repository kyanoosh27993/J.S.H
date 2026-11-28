/// صفحه پشتیبانی (N-02 + بند ۱۸) — اطلاعات سازنده + اعتبار کد فعال‌سازی
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/services/activation_service.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';

class SupportPage extends StatelessWidget {
  final AppSession session;
  const SupportPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final remaining = ActivationService.remainingDays(s.license);
    final expiryStr = s.license.activationExpiry.isEmpty
        ? '—'
        : shamsiDate(DateTime.parse(s.license.activationExpiry));
    final remainingFa = toPersianDigits('$remaining');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            Text('پشتیبانی برنامه', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'در صورت بروز هرگونه مشکل در نصب، فعال‌سازی یا استفاده از برنامه، از راه‌های زیر با شرکت سازنده تماس بگیرید.',
              style: TextStyle(fontSize: 13.5, height: 1.9),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.business, size: 20),
                      SizedBox(width: 8),
                      Text(VendorInfo.companyName,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.phone_in_talk, size: 20),
                      const SizedBox(width: 8),
                      Text('تلفن واحد پشتیبانی: ${toPersianDigits(VendorInfo.supportPhone)}',
                          style: const TextStyle(fontSize: 13.5)),
                    ]),
                    const SizedBox(height: 6),
                    const Row(children: [
                      Icon(Icons.location_on, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text(VendorInfo.address, style: TextStyle(fontSize: 13.5))),
                    ]),
                    const SizedBox(height: 6),
                    const Row(children: [
                      Icon(Icons.email, size: 20),
                      SizedBox(width: 8),
                      Text('ایمیل: ${VendorInfo.email}', style: TextStyle(fontSize: 13.5)),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // اعتبار کد فعال‌سازی (بند ۱۸)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.key_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('اعتبار کد فعال‌سازی برنامه',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text(
                        remaining > 7
                            ? 'مدت اعتبار باقیمانده: $remainingFa روز'
                            : remaining > 0
                                ? 'هشدار: فقط $remainingFa روز اعتبار باقیمانده'
                                : 'اعتبار به پایان رسیده است',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: remaining > 7
                              ? Colors.green.shade700
                              : remaining > 0
                                  ? Colors.orange.shade800
                                  : Colors.red.shade700,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('تاریخ پایان اعتبار: $expiryStr',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 10),
                    const Divider(height: 16),
                    const Text('شماره شناسه دستگاه:',
                        style: TextStyle(fontSize: 12.5, color: Colors.blueGrey)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: SelectableText(
                          s.license.fingerprint.isEmpty
                              ? '—'
                              : ActivationService.displayDeviceId(s.license.fingerprint),
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'کپی شناسه دستگاه',
                        icon: const Icon(Icons.copy, size: 17),
                        onPressed: s.license.fingerprint.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(
                                    text: s.license.fingerprint));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('شناسه دستگاه کپی شد')));
                                }
                              },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'قواعد لایسنس تجاری:\n'
              '• نسخه خریداری‌شده فقط روی یک رایانه فعال می‌شود.\n'
              '• سقف نصب مجدد روی همان رایانه همان عددی است که در کد فعال‌سازی شما ثبت شده؛ در صورت اتمام سهمیه، فقط از طریق پشتیبانی باز می‌شود.\n'
              '• فعال‌سازی برنامه فقط با کد فعال‌سازی سازنده انجام می‌شود (بدون نیاز به ایمیل).',
              style: TextStyle(fontSize: 13, height: 1.9, color: Colors.blueGrey),
            ),
            const Divider(height: 28),
            Text('نسخه برنامه', style: Theme.of(context).textTheme.titleMedium),
            Text('داشبورد تعمیرات و خدمات — نسخه ${toPersianDigits(AppInfo.version)}',
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
