/// اسکن بارکد/QR سفارش با دوربین گوشی — فاز ۶ب (بند ۱۰)
///
/// صفحه‌ای ساده روی بسته `mobile_scanner`: اولین بارکد شناسایی‌شده با
/// `Navigator.pop(rawValue)` به صفحه فراخوان برمی‌گردد تا شماره سفارش از
/// روی برچسب/QR خوانده شود.
/// - فقط روی اندروید/iOS کار می‌کند؛ ویندوز اسکنر دوربین ندارد و صفحه
///   ساده «اسکنر فقط روی موبایل» نشان داده می‌شود
/// - چراغ قوه برای محیط کم‌نور + راهنمای فارسی
/// - جلوگیری از pop دوباره با پرچم `_popped` (detect پشت‌سرهم)
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// صفحه اسکنر — روی ویندوز/لینوکس/مک صفحه پیام ساده، روی موبایل دوربین
class BarcodeScannerPage extends StatelessWidget {
  const BarcodeScannerPage({super.key});

  /// اسکنر دوربین فقط روی گوشی/تبلت معنا دارد
  static bool get _isMobile =>
      Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    if (!_isMobile) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('اسکن بارکد سفارش')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner,
                    size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('اسکنر فقط روی موبایل'),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('بازگشت'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const _MobileScannerView();
  }
}

/// نمای دوربین — با کنترلر دستی تا خطای راه‌اندازی (مثلا نبود مجوز دوربین)
/// بدون «صفحه قرمز» مدیریت شود
class _MobileScannerView extends StatefulWidget {
  const _MobileScannerView();

  @override
  State<_MobileScannerView> createState() => _MobileScannerViewState();
}

class _MobileScannerViewState extends State<_MobileScannerView> {
  final MobileScannerController _controller =
      MobileScannerController(autoStart: false);
  bool _popped = false; // پرچم جلوگیری از pop دوباره
  bool _startFailed = false;
  String _startError = '';
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _startFailed = true;
        _startError = '$e';
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_popped) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _popped = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // چراغ قوه روی بعضی دستگاه‌ها در دسترس نیست — بی‌صدا رد می‌شود
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('اسکن بارکد سفارش'),
          actions: [
            IconButton(
              tooltip: 'چراغ قوه',
              onPressed: _startFailed ? null : _toggleTorch,
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _startFailed
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'دوربین در دسترس نیست:\n$_startError',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  : MobileScanner(controller: _controller, onDetect: _onDetect),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.black87,
              child: const Text(
                'بارکد یا QR سفارش را در کادر بگیرید',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
