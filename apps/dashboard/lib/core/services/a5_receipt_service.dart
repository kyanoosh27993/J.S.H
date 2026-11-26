/// فرم رسید سه‌برگی A5 — فاز ۴ (بند ۱۰ + بند ۶ جدید)
/// مطابق فرم کاغذی فروشگاه: برگ مشتری، برگ فروشگاه (با جدول اقلام) و برگ بایگانی.
/// - لوگو/نام فروشگاه در سربرگ؛ مهر/امضا/لوگو به انتخاب کاربر (بند ۶)
/// - متن تعهدات justify و RTL؛ پترن قفل به‌جای امضا (بند ۷)
/// - اعلام «مبلغ ممکن است بعد از بررسی دستگاه اضافه شود» (بند ۱۰)
/// - اگر تاریخ تحویل ثبت نشده باشد: «تاریخ تحویل بعد از بررسی دستگاه به مشتری اعلام می گردد»
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import '../utils.dart';
import 'pdf_service.dart';
import 'shop_settings_service.dart';

class A5ReceiptService {
  /// فونت‌ها — از سرویس PDF اصلی گرفته می‌شود تا یک‌بار لود شود
  static pw.Font get regular => PdfService.regularFont;
  static pw.Font get bold => PdfService.boldFont;

  /// ساخت PDF سه‌برگی — خروجی مسیر فایل
  /// [sheets] = (برگ مشتری، برگ فروشگاه، برگ بایگانی)
  /// [withStamp/withSignature/withLogo] = انتخاب کاربر برای تصاویر فروشگاه (بند ۶)
  static Future<String> build({
    required Map<String, String> shop,
    required Ticket ticket,
    required Customer customer,
    required Device device,
    required List<TicketItem> items,
    required (bool, bool, bool) sheets,
    bool withStamp = true,
    bool withSignature = true,
    bool withLogo = true,
  }) async {
    await PdfService.ensureFonts();
    final doc = pw.Document();
    final logoBytes = withLogo ? await ShopSettingsService.bytesOf(ShopImage.logo) : null;
    final stampBytes = withStamp ? await ShopSettingsService.bytesOf(ShopImage.stamp) : null;
    final sigBytes =
        withSignature ? await ShopSettingsService.bytesOf(ShopImage.signature) : null;
    final accessories = await ShopSettingsService.loadAccessories();
    final remaining = ticket.estimateAmount - ticket.depositAmount;

    pw.Widget? img(List<int>? bytes, {double w = 60}) {
      if (bytes == null) return null;
      try {
        return pw.Image(pw.MemoryImage(Uint8List.fromList(bytes)),
            width: w, height: w);
      } catch (_) {
        return null;
      }
    }

    // ── سربرگ مشترک ──
    pw.Widget header() => pw.Column(children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shop['name'] ?? '',
                        style: pw.TextStyle(font: bold, fontSize: 15)),
                    pw.Text(
                        'آدرس: ${shop['address'] ?? ''}  —  تلفن: ${toPersianDigits(shop['phone'] ?? '')}',
                        style: pw.TextStyle(font: regular, fontSize: 8)),
                    pw.Text(
                        'تلفن: ${toPersianDigits(shop['phone'] ?? '')}',
                        style: pw.TextStyle(font: regular, fontSize: 8)),
                  ],
                ),
              ),
              if (logoBytes != null) img(logoBytes, w: 52)!,
            ],
          ),
          pw.Divider(color: PdfColors.grey600, height: 6),
        ]);

    // فیلد با خط نقطه‌چین — مطابق فرم کاغذی
    pw.Widget field(String label, String value, {double labelW = 88}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: labelW,
                child: pw.Text('$label :',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: regular, fontSize: 9)),
              ),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.only(bottom: 2, right: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                          color: PdfColors.grey500,
                          width: 0.6,
                          style: pw.BorderStyle.dashed),
                    ),
                  ),
                  child: pw.Text(value.isEmpty ? '' : value,
                      style: pw.TextStyle(font: regular, fontSize: 9.5)),
                ),
              ),
            ],
          ),
        );

    // تعهدات — justify و RTL (بند ۱۰)
    pw.Widget pledges() => pw.Container(
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('تعهدات :',
                  style: pw.TextStyle(font: bold, fontSize: 9.5)),
              pw.SizedBox(height: 3),
              pw.Text(
                'اینجانب ${customer.name} فرزند ${customer.fatherName} به شماره ملی '
                '${toPersianDigits(customer.nationalId)} در صورت بروز هرگونه مشکل و خاموش شدن دستگاه خود '
                'نسبت به این فروشگاه هیچ‌گونه ادعایی ندارم.',
                textAlign: pw.TextAlign.justify,
                style: pw.TextStyle(font: regular, fontSize: 8.6, lineSpacing: 2),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'حاضر هستم در صورت نیاز به هزینه و اجزاء مربوطه آن را پرداخت نمایم. مبلغ پیش‌فاکتور '
                'اولیه، طبق برآورد چشم‌انداز اولیه می‌باشد و در صورت افزایش قطعات و هزینه‌های جانبی، '
                'مبلغ نهایی تغییر خواهد کرد.',
                textAlign: pw.TextAlign.justify,
                style: pw.TextStyle(font: regular, fontSize: 8.6, lineSpacing: 2),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'در صورت تأمین قطعات تا سقف ${moneyToman(ticket.estimateAmount)} فروشگاه متعهد به انجام تعمیر '
                'است؛ در غیر این صورت مبلغ پیش‌پرداخت بدون کسر کسر ۱۰٪ برگشت داده می‌شود.',
                textAlign: pw.TextAlign.justify,
                style: pw.TextStyle(font: regular, fontSize: 8.6, lineSpacing: 2),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'در سفارشات قابل بررسی تا ۳۰/۰۰۰/۰۰۰ تومان حدود مسئولیت نگهداری دستگاه بر عهده فروشگاه است.',
                textAlign: pw.TextAlign.justify,
                style: pw.TextStyle(font: regular, fontSize: 8.6, lineSpacing: 2),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                  'مبلغ پیش‌فاکتور: ${moneyToman(ticket.estimateAmount)} — بیعانه دریافتی: ${moneyToman(ticket.depositAmount)} — مانده پیش‌فاکتور: ${moneyToman(remaining < 0 ? 0 : remaining)}',
                  style: pw.TextStyle(font: bold, fontSize: 8.8)),
              pw.Text('این مبلغ ممکن است بعد از بررسی دستگاه اضافه شود.',
                  style: pw.TextStyle(font: regular, fontSize: 8,
                      color: PdfColors.red700)),
              pw.SizedBox(height: 4),
              // لوازم همراه با مربع تیک — بند ۱۰
              pw.Wrap(
                spacing: 10,
                children: [
                  for (final a in accessories)
                    pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                      pw.Container(
                        width: 9,
                        height: 9,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
                        ),
                      ),
                      pw.SizedBox(width: 3),
                      pw.Text(a,
                          style: pw.TextStyle(font: regular, fontSize: 8.4)),
                    ]),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('(امضا)',
                      style: pw.TextStyle(font: regular, fontSize: 7.5,
                          color: PdfColors.grey600)),
                  pw.Text('نام و امضا تحویل گیرنده :',
                      style: pw.TextStyle(font: regular, fontSize: 8.6)),
                ],
              ),
            ],
          ),
        );

    // پترن قفل — شبکه نقاط با ترتیب مسیر (بند ۷)
    pw.Widget lockPatternBox() {
      final order = ticket.lockPattern
          .split('-')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .where((e) => e >= 1 && e <= 9)
          .toList();
      String labelFor(int n) => order.contains(n)
          ? toPersianDigits('${order.indexOf(n) + 1}')
          : '•';
      return pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
        ),
        child: pw.Column(children: [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            children: [
              for (var r = 0; r < 3; r++)
                pw.TableRow(children: [
                  for (var c = 0; c < 3; c++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(
                          labelFor(r * 3 + c + 1),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              font: order.contains(r * 3 + c + 1)
                                  ? bold
                                  : regular,
                              fontSize: 9,
                              color: order.contains(r * 3 + c + 1)
                                  ? PdfColors.blue800
                                  : PdfColors.grey600)),
                    ),
                ]),
            ],
          ),
          pw.Text('پترن قفل دستگاه',
              style: pw.TextStyle(font: regular, fontSize: 7)),
        ]),
      );
    }

    // ── برگ مشتری/بایگانی ──
    pw.Widget customerSheet({required bool archive}) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            header(),
            pw.Center(
              child: pw.Text(
                  archive ? 'موافق سبد حسبی — بایگانی' : 'رسید سپردن دستگاه',
                  style: pw.TextStyle(font: bold, fontSize: 12)),
            ),
            pw.SizedBox(height: 4),
            field('تاریخ ورود', shamsiDate(ticket.intakeDate)),
            field('تاریخ ورد/تحویل',
                ticket.dueUnknown
                    ? 'بعد از بررسی دستگاه به مشتری اعلام می گردد'
                    : '${shamsiDate(ticket.dueDate)} — ${toPersianDigits(ticket.dueTime)}'),
            field('نام مشتری', customer.name),
            field('شماره سریال', toPersianDigits(device.serial)),
            field('مدل', device.model),
            field('گارانتی', ''),
            field('وضعیت ظاهری کالا',
                ticket.phoneState.isEmpty ? '' : ticket.phoneState),
            field('عیب اعلامی', ticket.defect),
            field('شماره رسید', toPersianDigits(ticket.code)),
            pw.SizedBox(height: 6),
            pledges(),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(children: [
                  if (ticket.lockPattern.isNotEmpty) ...[
                    lockPatternBox(),
                    pw.Text('پترن قفل دستگاه',
                        style: pw.TextStyle(font: regular, fontSize: 7)),
                  ],
                ]),
                pw.Column(children: [
                  if (sigBytes != null) img(sigBytes, w: 46)!,
                  pw.Container(
                    width: 90,
                    child: pw.Column(children: [
                      pw.Container(
                        width: 90,
                        height: 1,
                        color: PdfColors.grey600,
                      ),
                      pw.Text('امضای مشتری',
                          style: pw.TextStyle(font: regular, fontSize: 8)),
                    ]),
                  ),
                ]),
                pw.Column(children: [
                  if (stampBytes != null) img(stampBytes, w: 46)!,
                  pw.Container(
                    width: 90,
                    child: pw.Column(children: [
                      pw.Container(
                        width: 90,
                        height: 1,
                        color: PdfColors.grey600,
                      ),
                      pw.Text('مهر و امضای فروشگاه',
                          style: pw.TextStyle(font: regular, fontSize: 8)),
                    ]),
                  ),
                ]),
              ],
            ),
          ],
        );

    // ── برگ فروشگاه — با جدول اقلام (مطابق فرم کاغذی) ──
    pw.Widget shopSheet() {
      final rows = <List<String>>[];
      for (var i = 0; i < 5; i++) {
        if (i < items.length) {
          final it = items[i];
          rows.add([
            toPersianDigits('${i + 1}'),
            '${it.description} × ${toPersianDigits('${it.qty}')}',
            it.price > 0 ? money(it.price * it.qty) : '',
          ]);
        } else {
          rows.add([toPersianDigits('${i + 1}'), '', '']);
        }
      }
      final total = items.fold<int>(0, (s, i) => s + i.price * i.qty);
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          header(),
          pw.Center(
            child: pw.Text('رسید سپردن — نسخه فروشگاه',
                style: pw.TextStyle(font: bold, fontSize: 12)),
          ),
          pw.SizedBox(height: 4),
          field('تاریخ ورود', shamsiDate(ticket.intakeDate)),
          field('نام مشتری', customer.name),
          field('تلفن', toPersianDigits(customer.phone)),
          field('مدل دستگاه', device.model),
          field('شماره رسید', toPersianDigits(ticket.code)),
          pw.SizedBox(height: 6),
          // جدول اقلام
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.7),
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('ردیف', bold, 9),
                  _cell('توضیحات و قیمت توری نشده', bold, 9),
                  _cell('مبلغ', bold, 9),
                ],
              ),
              for (final r in rows)
                pw.TableRow(children: [
                  _cell(r[0], regular, 8.5),
                  _cell(r[1], regular, 8.5),
                  _cell(r[2], regular, 8.5),
                ]),
              pw.TableRow(children: [
                _cell('', regular, 8.5),
                _cell('جمع صفحه', bold, 8.5),
                _cell(total > 0 ? money(total) : '', bold, 8.5),
              ]),
              pw.TableRow(children: [
                _cell('', regular, 8.5),
                _cell('تحویل گردید', bold, 8.5),
                _cell('', regular, 8.5),
              ]),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (stampBytes != null) img(stampBytes, w: 44)! else pw.SizedBox(),
              pw.Column(children: [
                pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                pw.Text('مهر و امضای فروشگاه',
                    style: pw.TextStyle(font: regular, fontSize: 8)),
              ]),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('امضا',
              style: pw.TextStyle(font: regular, fontSize: 7.5,
                  color: PdfColors.grey600)),
        ],
      );
    }

    // افزودن صفحات انتخابی — بند ۱۰: کاربر تیک می‌زند کدام برگه‌ها پرینت شوند
    final (s1, s2, s3) = sheets;
    if (s1) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        build: (_) => customerSheet(archive: false),
      ));
    }
    if (s2) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        build: (_) => shopSheet(),
      ));
    }
    if (s3) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        build: (_) => customerSheet(archive: true),
      ));
    }
    if (!s1 && !s2 && !s3) {
      // هیچ برگی انتخاب نشده — برگ مشتری به‌عنوان پیش‌فرض
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        build: (_) => customerSheet(archive: false),
      ));
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'receipts');
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, '${ticket.code}-A5.pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  static pw.Widget _cell(String text, pw.Font font, double size) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: size)),
      );
}
