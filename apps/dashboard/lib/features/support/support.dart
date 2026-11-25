/// صفحه پشتیبانی (N-02) — اطلاعات شرکت سازنده برای خریدار برنامه
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
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
            const Text(
              'قواعد لایسنس تجاری:\n'
              '• نسخه خریداری‌شده فقط روی یک رایانه فعال می‌شود.\n'
              '• حداکثر ۳ بار نصب روی همان رایانه مجاز است؛ نصب چهارم فقط از طریق پشتیبانی باز می‌شود.\n'
              '• پس از هر نصب، گزارش فعال‌سازی به شرکت سازنده ارسال می‌شود.',
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
