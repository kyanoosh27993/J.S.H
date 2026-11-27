/// سرویس PDF — رسید پذیرش با سربرگ فروشگاه، فرم دیجیتال F-12-1
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants.dart';
import '../models.dart';
import '../utils.dart';

class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// فونت‌های عمومی برای سرویس‌های PDF دیگر (فرم A5)
  static pw.Font get regularFont => _regular!;
  static pw.Font get boldFont => _bold!;
  static bool get fontsReady => _regular != null;
  static Future<void> ensureFonts() => _ensureFonts();

  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    final regData =
        await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf');
    _regular = pw.Font.ttf(regData);
    _bold = pw.Font.ttf(boldData);
  }

  static Future<pw.MemoryImage?> _logo() async {
    try {
      final data = await rootBundle.load(AppInfo.logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// حسابرسی (قاعده ۱۰): بایت‌های امضای خراب هرگز نباید PDF را کرش کنند —
  /// فقط PNG یا JPEG معتبر پذیرفته می‌شود.
  static pw.MemoryImage? _safeImage(Uint8List bytes) {
    if (bytes.length < 8) return null;
    final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!isPng && !isJpeg) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// مسیر پوشه رسیدها
  static Future<String> receiptsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'receipts');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// PDF رسید پذیرش (فرم سپردن دیجیتال — مطابق فرم کاغذی فروشگاه)
  static Future<String> buildIntakeReceipt({
    required Map<String, String> shop,
    required Ticket ticket,
    required Customer customer,
    required Device device,
    required Uint8List signatureBytes,
  }) async {
    await _ensureFonts();
    final logo = await _logo();
    final doc = pw.Document();

    final accessories = ticket.accessories.isEmpty
        ? 'ثبت نشده'
        : ticket.accessories.join('، ');

    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 130,
                child: pw.Text(label,
                    style: pw.TextStyle(font: _bold, fontSize: 10)),
              ),
              pw.Expanded(
                child: pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  ),
                  child: pw.Text(value,
                      style: pw.TextStyle(font: _regular, fontSize: 10)),
                ),
              ),
            ],
          ),
        );

    // کد QR رسید — فقط کد تیکت (هماهنگ با فرم A5)
    pw.Widget? qr;
    if (ticket.code.isNotEmpty) {
      try {
        final qrc =
            pw.QrCode.fromData(data: ticket.code);
        qr = pw.Container(
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          ),
          child: pw.QrImageView(
            qrCode: qrc,
            size: 40,
            padding: const pw.EdgeInsets.zero,
          ),
        );
      } catch (_) {
        qr = null;
      }
    }
    final signatureImage = _safeImage(signatureBytes);
    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          // سربرگ فروشگاه
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logo != null) pw.Image(logo, width: 46, height: 46),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(shop['name'] ?? '',
                      style: pw.TextStyle(font: _bold, fontSize: 14)),
                  pw.Text(
                      'آدرس: ${shop['address'] ?? ''} — تلفن: ${toPersianDigits(shop['phone'] ?? '')}',
                      style: pw.TextStyle(font: _regular, fontSize: 8)),
                ],
              ),
              if (qr != null) qr!,
            ],
          ),
          pw.Divider(color: PdfColors.grey600),
          pw.Center(
            child: pw.Text('رسید پذیرش / سپردن دستگاه',
                style: pw.TextStyle(font: _bold, fontSize: 13)),
          ),
          pw.SizedBox(height: 6),
          row('شماره رسید', toPersianDigits(ticket.code)),
          row('تاریخ ورود', shamsiDate(ticket.intakeDate)),
          row('تاریخ و ساعت تحویل',
              '${shamsiDate(ticket.dueDate)} — ${toPersianDigits(ticket.dueTime)}'),
          row('نام مشتری', customer.name),
          row('نام پدر', customer.fatherName),
          row('شماره ملی', toPersianDigits(customer.nationalId)),
          row('تلفن', toPersianDigits(customer.phone)),
          row('مدل دستگاه', device.model),
          row('شماره سریال', toPersianDigits(device.serial)),
          row('عیب دستگاه اعلامی', ticket.defect),
          row('وضعیت تلفنی دستگاه', ticket.phoneState.isEmpty ? '-' : ticket.phoneState),
          row('قیمت احتمالی', moneyToman(ticket.estimateAmount)),
          row('بیعانه دریافتی', moneyToman(ticket.depositAmount)),
          row('لوازم همراه', accessories),
          pw.SizedBox(height: 8),
          // متن اقرارنامه فرم کاغذی
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                    'توجه: آورنده قبض، صحت گوشی شناخته می‌شود و متعلقات تحویل داده شده به مشتری همان است که در بالا آمده است.',
                    style: pw.TextStyle(font: _bold, fontSize: 8.5)),
                pw.SizedBox(height: 4),
                pw.Text(
                    'اینجانب ${customer.name} فرزند ${customer.fatherName} به شماره ملی ${customer.nationalId} در صورت بروز هرگونه مشکل و خاموش شدن گوشی خود نسبت به این فروشگاه هیچ‌گونه ادعایی ندارم.',
                    style: pw.TextStyle(font: _regular, fontSize: 8.5)),
                pw.SizedBox(height: 4),
                pw.Text(
                    'دستگاه حداکثر تا ۳۰ روز بعد از تاریخ ورود نزد فروشگاه می‌ماند؛ در غیر این صورت فروشگاه مسئول نگهداری آن نخواهد بود.',
                    style: pw.TextStyle(font: _regular, fontSize: 8.5)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                if (signatureBytes.isNotEmpty)
                  if (signatureImage != null)
                    pw.Image(signatureImage, width: 90, height: 36),
                pw.Text('امضای مشتری',
                    style: pw.TextStyle(font: _regular, fontSize: 8)),
              ]),
              pw.Column(children: [
                pw.SizedBox(height: 30),
                pw.Text('امضای فروشنده',
                    style: pw.TextStyle(font: _regular, fontSize: 8)),
              ]),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
              'پشتیبانی برنامه: ${VendorInfo.companyName} — ${toPersianDigits(VendorInfo.supportPhone)} — ${VendorInfo.email}',
              style: pw.TextStyle(font: _regular, fontSize: 7,
                  color: PdfColors.grey700)),
        ],
      ),
    );

    final path = p.join(await receiptsDir(), '${ticket.code}.pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }
}
