/// صفحه «اسکن و دوربین» گوشی (v0.12.4) — دوربین آنلاین برای اسکن بارکد/QR،
/// عکس‌برداری و انتخاب اسناد جهت اتچ‌کردن در سفارشات روی PC.
/// فقط روی اندروید در منو ظاهر می‌شود.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants.dart';
import '../../core/services/pair_service.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _camera = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode, BarcodeFormat.code128]);
  List<Map<String, Object?>> _results = [];
  Map<String, Object?>? _selected;
  String _manual = '';
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    final code = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
    if (code == null || code.isEmpty || _busy) return;
    await _lookup(code);
  }

  Future<void> _lookup(String q) async {
    setState(() {
      _busy = true;
      _message = 'در حال جستجوی «$q»…';
    });
    final res = await PairService.scan(q);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = res;
      _selected = res.isNotEmpty ? res.first : null;
      _message = res.isEmpty ? 'سفارشی برای «$q» یافت نشد' : null;
    });
  }

  Future<void> _pickAndUpload(bool fromCamera) async {
    final ticketId = _selected?['id'] as int?;
    if (ticketId == null) {
      setState(() => _message = 'اول سفارش را با اسکن یا جستجو انتخاب کنید');
      return;
    }
    final picker = ImagePicker();
    final XFile? f = fromCamera
        ? await picker.pickImage(source: ImageSource.camera, imageQuality: 80)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await PairService.uploadAttachment(
        ticketId, await f.readAsBytes(), f.name,
        note: fromCamera ? 'عکس از دوربین موبایل' : 'سند انتخابی از موبایل');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok
          ? 'عکس به سفارش ${_selected!['code']} اضافه شد ✓'
          : 'ارسال به PC ناموفق بود — اتصال شبکه را چک کنید';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('اسکن بارکد/QR و دوربین')),
        body: Column(
          children: [
            Expanded(
              flex: 4,
              child: Stack(children: [
                MobileScanner(controller: _camera, onDetect: _onDetect),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Card(
                    color: Colors.black.withOpacity(0.7),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _message ?? 'بارکد یا QR را داخل کادر بگیرید — نسخه ${AppInfo.version}',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                              labelText: 'جستجوی دستی (کد رسید/سریال/نام)',
                              border: OutlineInputBorder(),
                              isDense: true),
                          onChanged: (v) => _manual = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy || _manual.trim().isEmpty
                            ? null
                            : () => _lookup(_manual.trim()),
                        child: const Text('جستجو'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (_results.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (c, i) {
                            final r = _results[i];
                            final sel = _selected?['id'] == r['id'];
                            return Card(
                              color: sel
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : null,
                              child: ListTile(
                                dense: true,
                                leading: Icon(sel
                                    ? Icons.check_circle
                                    : Icons.receipt_long),
                                title: Text('${r['code']} — ${r['customer']}'),
                                subtitle: Text(
                                    '${r['model']} — وضعیت: ${r['status']}'),
                                onTap: () =>
                                    setState(() => _selected = r),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      const Expanded(
                        child: Center(
                          child: Text('سفارشی انتخاب نشده',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                    Row(children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              _busy ? null : () => _pickAndUpload(true),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('عکس برای سفارش'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              _busy ? null : () => _pickAndUpload(false),
                          icon: const Icon(Icons.attach_file),
                          label: const Text('انتخاب سند'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
