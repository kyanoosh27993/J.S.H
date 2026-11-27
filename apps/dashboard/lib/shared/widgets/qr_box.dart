/// کد QR سند — فاز ۵ (بند ۶ جدید)
/// روی سفارش/پیش‌فاکتور/فاکتور نمایش داده می‌شود؛ با اسکن یا تایپ شماره
/// سند در صفحه مربوطه باز می‌شود (اسکنر دوربین در فاز ۸ متصل می‌شود).
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils.dart';

class QrBox extends StatelessWidget {
  final String data;
  final double size;
  const QrBox({super.key, required this.data, this.size = 72});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: 'کد QR سند — ${toPersianDigits(data)}',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: QrImageView(
          data: data,
          size: size,
          backgroundColor: Colors.white,
          version: QrVersions.auto,
        ),
      ),
    );
  }
}
