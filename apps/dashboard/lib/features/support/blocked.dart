/// صفحه‌های بلاک — قفل لایسنس یا انتظار ارسال گزارش نصب (F-09 / N-03)
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

class BlockedPage extends StatelessWidget {
  final String title;
  final String message;
  final bool showRetry;
  final VoidCallback? onRetry;

  const BlockedPage({
    super.key,
    required this.title,
    required this.message,
    this.showRetry = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          color: const Color(0xFF1A2330),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(AppInfo.logoAsset, width: 72, height: 72),
                      const SizedBox(height: 14),
                      Text(title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13.5, height: 1.9)),
                      const SizedBox(height: 18),
                      Text(
                        'پشتیبانی: ${VendorInfo.companyName} — ${VendorInfo.phoneDisplay}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w600),
                      ),
                      Text('ایمیل: ${VendorInfo.email}',
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.blueGrey)),
                      if (showRetry) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('بررسی دوباره اتصال'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
