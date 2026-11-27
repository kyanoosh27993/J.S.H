/// فرم رسید سه‌برگی A5 — فاز ۵a (بند ۱ + ۱.۱۶ + ۱.۱۷ + ۱.۱۸ + ۱.۱۹)
/// بازسازی کامل مطابق فرم کاغذی واقعی فروشگاه:
///   برگ ۱) برگ مشتری  — سربرگ + فیلدها + اقرارنامه + متعلقات انتخابی + امضاء
///   برگ ۲) برگ فروشگاه — جدول ردیف/عیوب و قطعات تعویض‌شده/مبلغ با ۵ ردیف شماره‌دار
///         + «جمع بحروف ریال» + تلفن مشتری + کد حفاظتی (پترن قفل) + QR کد رسید
///   برگ ۳) برگ بایگانی — فرم «اقلام تحویل داده شده به مشتری» (بند ۱.۱۶/۱.۱۷)
/// نکات:
/// - مقادیر سربرگ فقط از تنظیمات فروشگاه (نام/آدرس/تلفن) — بدون مقدار ثابت
/// - اقلام جدول فقط از اقلام واقعی سفارش پر می‌شود؛ ردیف‌های خالی فقط شماره دارند (بند ۱.۱۸)
/// - مبالغ سفارش (برآورد/بیعانه/اقلام) در برگ فروشگاه نمایش داده می‌شود (بند ۱.۱۹)
/// - مربع‌های تیک متعلقات برای همه چاپ می‌شوند و فقط انتخاب‌شده‌ها علامت می‌خورند
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
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

  /// ساخت PDF سه‌برگی — خروجی مسیر فایل (مسیر پیش‌فرض اسناد برنامه)
  /// [sheets] = (برگ مشتری، برگ فروشگاه، برگ بایگانی) — سازگار با فراخوانی‌های قبلی
  /// [withStamp/withSignature/withLogo] = انتخاب کاربر برای تصاویر فروشگاه (بند ۶)
  /// [selectedAccessories] = متعلقات تیک‌خورده در فرم پذیرش؛ اگر null باشد از ticket
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
    List<String>? selectedAccessories,
  }) async {
    final bytes = await buildBytes(
      shop: shop,
      ticket: ticket,
      customer: customer,
      device: device,
      items: items,
      sheets: sheets,
      withStamp: withStamp,
      withSignature: withSignature,
      withLogo: withLogo,
      selectedAccessories: selectedAccessories,
    );
    final dir = await PdfService.receiptsDir();
    final path = p.join(dir, '${ticket.code}-A5.pdf');
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// ساخت بایت‌های PDF بدون نوشتن فایل — برای دیالوگ «ذخیره در محل دلخواه» (بند ۱.۱۴)
  static Future<Uint8List> buildBytes({
    required Map<String, String> shop,
    required Ticket ticket,
    required Customer customer,
    required Device device,
    required List<TicketItem> items,
    required (bool, bool, bool) sheets,
    bool withStamp = true,
    bool withSignature = true,
    bool withLogo = true,
    List<String>? selectedAccessories,
  }) async {
    await PdfService.ensureFonts();
    final doc = pw.Document();
    final logoBytes = withLogo ? await ShopSettingsService.bytesOf(ShopImage.logo) : null;
    final stampBytes = withStamp ? await ShopSettingsService.bytesOf(ShopImage.stamp) : null;
    final sigBytes =
        withSignature ? await ShopSettingsService.bytesOf(ShopImage.signature) : null;
    final allAccessories = await ShopSettingsService.loadAccessories();
    // متعلقات انتخاب‌شده — بند ۱۰: فقط تیک‌خورده‌ها علامت می‌خورند
    final selected = selectedAccessories ?? ticket.accessories;
    final remaining = ticket.estimateAmount - ticket.depositAmount;
    final totalItems = items.fold<int>(0, (s, i) => s + i.price * i.qty);

    pw.Widget? img(List<int>? bytes, {double w = 60}) {
      if (bytes == null) return null;
      try {
        return pw.Image(pw.MemoryImage(Uint8List.fromList(bytes)),
            width: w, height: w);
      } catch (_) {
        return null;
      }
    }

    // ── کد QR رسید — فقط کد تیکت (مطابق qr_box.dart اما بدون شماره فاکتور) ──
    pw.Widget qrBox({double size = 44}) {
      if (ticket.code.isEmpty) return pw.SizedBox();
      return pw.Container(
        width: size,
        height: size,
        padding: const pw.EdgeInsets.all(2),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
        ),
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: ticket.code,
          color: PdfColors.black,
        ),
      );
    }

    // ── سربرگ مشترک — فقط از تنظیمات فروشگاه (بند ۱) ──
    pw.Widget header({bool compact = false}) => pw.Column(children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shop['name'] ?? '',
                        style: pw.TextStyle(font: bold, fontSize: compact ? 11 : 14)),
                    if ((shop['address'] ?? '').isNotEmpty)
                      pw.Text('آدرس: ${shop['address']}',
                          style: pw.TextStyle(font: regular, fontSize: 7.5)),
                    // دو خط تلفن — «همراه» فقط اگر در تنظیمات باشد، وگرنه یک خط «تلفن»
                    if ((shop['mobile'] ?? '').isNotEmpty)
                      pw.Text('همراه: ${toPersianDigits(shop['mobile']!)}',
                          style: pw.TextStyle(font: regular, fontSize: 7.5)),
                    if ((shop['phone'] ?? '').isNotEmpty)
                      pw.Text('تلفن: ${toPersianDigits(shop['phone']!)}',
                          style: pw.TextStyle(font: regular, fontSize: 7.5)),
                  ],
                ),
              ),
              pw.SizedBox(width: 6),
              if (logoBytes != null) img(logoBytes, w: compact ? 34 : 48)!,
              qrBox(size: compact ? 34 : 44),
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

    // دو فیلد در یک سطر — مطابق چیدمان فرم کاغذی
    pw.Widget fieldPair(String l1, String v1, String l2, String v2) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(child: field(l1, v1)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: field(l2, v2)),
          ],
        );

    // مربع تیک متعلقات — همه با مربع، فقط انتخاب‌شده‌ها علامت (✓ جایگزین؟ فونت فارسی
    // از ✓ پشتیبانی می‌کند؛ برای اطمینان با ضربدر پرشده داخلی رندر می‌شود)
    pw.Widget checkbox(String label, {required bool checked}) => pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(
              width: 9,
              height: 9,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
              ),
              child: checked
                  ? pw.Container(color: PdfColors.grey800)
              : null,
            ),
            pw.SizedBox(width: 3),
            pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 8.4)),
          ],
        );

    pw.Widget accessoriesWrap({required bool onlySelected}) {
      final list = onlySelected
          ? allAccessories.where((a) => selected.contains(a)).toList()
          : allAccessories;
      if (list.isEmpty) {
        return pw.Text('ثبت نشده',
            style: pw.TextStyle(font: regular, fontSize: 8.4));
      }
      return pw.Wrap(spacing: 10, runSpacing: 3, children: [
        for (final a in list) checkbox(a, checked: selected.contains(a)),
      ]);
    }

    // متن اقرارنامه — همان منطق فرم پذیرش (terms در intake)
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

    // تاریخ و ساعت خروج از کارگاه / تحویل — با حالت بی‌تاریخ (بند ۱۰)
    String dueText() => ticket.dueUnknown
        ? 'بعد از بررسی دستگاه به مشتری اعلام می گردد'
        : '${shamsiDate(ticket.dueDate)} — ${toPersianDigits(ticket.dueTime)}';

    // ── برگ فروشگاه — جدول اصلی مطابق فرم کاغذی (بند ۱ + ۱.۱۹) ──
    pw.Widget shopSheet() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            header(),
            pw.Center(
              child: pw.Text('برگ فروشگاه',
                  style: pw.TextStyle(font: bold, fontSize: 12)),
            ),
            pw.SizedBox(height: 3),
            fieldPair('تاریخ ورود', shamsiDate(ticket.intakeDate),
                'تاریخ و ساعت خروج از کارگاه', dueText()),
            fieldPair('نام مشتری', customer.name, 'تلفن',
                toPersianDigits(customer.phone)),
            fieldPair('مدل', device.model,
                'شماره سریال', toPersianDigits(device.serial)),
            fieldPair('تعمیرکار', '',
                'کد حفاظتی', ticket.lockPattern.isEmpty ? '' : toPersianDigits(ticket.lockPattern)),
            field('عیب دستگاه', ticket.defect),
            field('وضعیت ظاهری دستگاه',
                ticket.phoneState.isEmpty ? '' : ticket.phoneState),
            pw.SizedBox(height: 5),
            // جدول اصلی — ستون اول سمت راست «ردیف»، دوم عیوب و قطعات (پهن‌ترین)، سوم مبلغ
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.7),
              columnWidths: const {
                0: pw.FixedColumnWidth(26),
                1: pw.FlexColumnWidth(),
                2: pw.FixedColumnWidth(74),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('ردیف', bold, 9),
                    _cell('عیـوب و قطعـات تعویض شـده', bold, 9),
                    _cell('مبـلـغ', bold, 9),
                  ],
                ),
                // ۵ ردیف شماره‌دار — فقط اقلام واقعی سفارش (بند ۱.۱۸)؛ خالی‌ها فقط شماره
                for (var i = 0; i < 5; i++)
                  pw.TableRow(children: [
                    _cell(toPersianDigits('${i + 1}'), regular, 8.5),
                    _cell(
                        i < items.length
                            ? (items[i].qty > 1
                                ? '${items[i].description} × ${toPersianDigits('${items[i].qty}')}'
                                : items[i].description)
                            : '',
                        regular, 8.5),
                    _cell(
                        i < items.length && items[i].price > 0
                            ? money(items[i].price * items[i].qty)
                            : '',
                        regular, 8.5),
                  ]),
                // جمع مبالغ — بند ۱.۱۹: مبالغ اضافه‌شده در سفارشات همین‌جا نمایش داده می‌شود
                pw.TableRow(children: [
                  _cell('', regular, 8.5),
                  _cell('جمع مبالغ', bold, 8.5),
                  _cell(totalItems > 0 ? money(totalItems) : '', bold, 8.5),
                ]),
              ],
            ),
            // «جمع بحروف ریال» — سطر یکپارچه زیر جدول (بدون پشتیبانی colspan در جدول)
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700, width: 0.7),
              ),
              child: pw.Row(
                children: [
                  pw.Text('جمع بحروف ریال :',
                      style: pw.TextStyle(font: bold, fontSize: 8.5)),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                              color: PdfColors.grey500,
                              width: 0.6,
                              style: pw.BorderStyle.dashed),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            // متعلقات — همه با مربع تیک، فقط انتخاب‌شده‌ها علامت
            pw.Text('متعلقات دستگاه :',
                style: pw.TextStyle(font: bold, fontSize: 8.8)),
            pw.SizedBox(height: 2),
            accessoriesWrap(onlySelected: false),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (ticket.lockPattern.isNotEmpty)
                  pw.SizedBox(width: 86, height: 60, child: lockPatternBox()),
                pw.Column(children: [
                  if (stampBytes != null) img(stampBytes, w: 44)!,
                  pw.Container(width: 90, child: pw.Column(children: [
                    pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                    pw.Text('مهر و امضای فروشگاه',
                        style: pw.TextStyle(font: regular, fontSize: 8)),
                  ])),
                ]),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text('امضا',
                style: pw.TextStyle(font: regular, fontSize: 7.5,
                    color: PdfColors.grey600)),
          ],
        );

    // ── برگ مشتری (برگ ۱) — مطابق فرم کاغذی ──
    pw.Widget customerSheet() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            header(),
            pw.Center(
              child: pw.Text('رسید سپردن دستگاه — برگ مشتری',
                  style: pw.TextStyle(font: bold, fontSize: 12)),
            ),
            pw.SizedBox(height: 3),
            fieldPair('تاریخ ورود', shamsiDate(ticket.intakeDate),
                'تاریخ و ساعت تحویل', dueText()),
            fieldPair('نام مشتری', customer.name, 'مدل دستگاه', device.model),
            fieldPair('شماره سریال', toPersianDigits(device.serial),
                'هزینه احتمالی', moneyToman(ticket.estimateAmount)),
            fieldPair('عیب دستگاه', ticket.defect,
                'بیعانه', moneyToman(ticket.depositAmount)),
            field('تلفن', toPersianDigits(customer.phone)),
            pw.SizedBox(height: 4),
            pledges(),
            pw.SizedBox(height: 5),
            // فقط متعلقات انتخاب‌شده — بند ۱.۱۸
            pw.Text('متعلقات تحویل داده شده به مشتری:',
                style: pw.TextStyle(font: bold, fontSize: 8.8)),
            pw.SizedBox(height: 2),
            accessoriesWrap(onlySelected: true),
            pw.SizedBox(height: 5),
            pw.Text(
                'اینجانب ${customer.name.isNotEmpty ? customer.name : "........"} تمام موارد فوق را با دقت مطالعه نموده و می‌پذیرم.',
                style: pw.TextStyle(font: regular, fontSize: 8.8)),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(children: [
                  pw.Text('نام و امضاء تحویل گیرنده:',
                      style: pw.TextStyle(font: regular, fontSize: 8.6)),
                  pw.SizedBox(height: 4),
                  pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                ]),
                pw.Column(children: [
                  if (sigBytes != null) img(sigBytes, w: 46)!,
                  pw.Container(
                    width: 90,
                    child: pw.Column(children: [
                      pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                      pw.Text('امضاء مشتري',
                          style: pw.TextStyle(font: regular, fontSize: 8)),
                    ]),
                  ),
                ]),
                pw.Column(children: [
                  if (stampBytes != null) img(stampBytes, w: 40)!,
                  pw.Container(
                    width: 90,
                    child: pw.Column(children: [
                      pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                      pw.Text('مهر و امضای فروشگاه',
                          style: pw.TextStyle(font: regular, fontSize: 8)),
                    ]),
                  ),
                ]),
              ],
            ),
          ],
        );

    // ── برگ بایگانی (برگ ۳) — فرم اقلام تحویل داده شده (بند ۱.۱۶/۱.۱۷) ──
    pw.Widget archiveSheet() {
      final rows = <pw.TableRow>[];
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        rows.add(pw.TableRow(children: [
          _cell(toPersianDigits('${i + 1}'), regular, 8.5),
          _cell(
              it.qty > 1
                  ? '${it.description} × ${toPersianDigits('${it.qty}')}'
                  : it.description,
              regular, 8.5),
          _cell(it.price > 0 ? money(it.price * it.qty) : '', regular, 8.5),
        ]));
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          header(compact: true),
          pw.Center(
            child: pw.Text('برگ بایگانی — اقلام تحویل داده شده به مشتری',
                style: pw.TextStyle(font: bold, fontSize: 11.5)),
          ),
          pw.SizedBox(height: 4),
          fieldPair('تاریخ و ساعت تحویل', dueText(),
              'شماره رسید', toPersianDigits(ticket.code)),
          field('نام مشتری', customer.name),
          field('مدل دستگاه', device.model),
          field('عیب دستگاه', ticket.defect),
          pw.SizedBox(height: 4),
          pw.Text('متعلقات تحویل داده شده به مشتری:',
              style: pw.TextStyle(font: bold, fontSize: 8.8)),
          pw.SizedBox(height: 2),
          accessoriesWrap(onlySelected: true),
          pw.SizedBox(height: 5),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.7),
            columnWidths: const {
              0: pw.FixedColumnWidth(26),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(74),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('ردیف', bold, 9),
                  _cell('شرح کالا', bold, 9),
                  _cell('مبلغ', bold, 9),
                ],
              ),
              if (rows.isEmpty)
                pw.TableRow(children: [
                  _cell(toPersianDigits('1'), regular, 8.5),
                  _cell('', regular, 8.5),
                  _cell('', regular, 8.5),
                ])
              else
                ...rows,
              pw.TableRow(children: [
                _cell('', regular, 8.5),
                _cell('تحویل گردید', bold, 8.5),
                _cell(totalItems > 0 ? money(totalItems) : '', bold, 8.5),
              ]),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                pw.Text('امضاء تحویل گیرنده',
                    style: pw.TextStyle(font: regular, fontSize: 8.4)),
              ]),
              pw.Column(children: [
                if (sigBytes != null) img(sigBytes, w: 44)!,
                pw.Container(
                  width: 90,
                  child: pw.Column(children: [
                    pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                    pw.Text('امضاء مشتری',
                        style: pw.TextStyle(font: regular, fontSize: 8.4)),
                  ]),
                ),
              ]),
              pw.Column(children: [
                if (stampBytes != null) img(stampBytes, w: 40)!,
                pw.Container(
                  width: 90,
                  child: pw.Column(children: [
                    pw.Container(width: 90, height: 1, color: PdfColors.grey600),
                    pw.Text('مهر و امضای فروشگاه',
                        style: pw.TextStyle(font: regular, fontSize: 8.4)),
                  ]),
                ),
              ]),
            ],
          ),
        ],
      );
    }

    // افزودن صفحات انتخابی — بند ۱۰: کاربر تیک می‌زند کدام برگه‌ها پرینت شوند
    final (s1, s2, s3) = sheets;
    pw.Page page(pw.Widget Function() body) => pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(18),
          textDirection: pw.TextDirection.rtl,
          build: (_) => body(),
        );
    var added = 0;
    if (s1) {
      doc.addPage(page(customerSheet));
      added++;
    }
    if (s2) {
      doc.addPage(page(shopSheet));
      added++;
    }
    if (s3) {
      doc.addPage(page(archiveSheet));
      added++;
    }
    if (added == 0) {
      // هیچ برگی انتخاب نشده — برگ مشتری به‌عنوان پیش‌فرض
      doc.addPage(page(customerSheet));
    }

    return await doc.save();
  }

  /// ذخیره PDF در محل دلخواه کاربر (بند ۱.۱۴) — دیالوگ file_selector؛
  /// اگر کاربر انصراف داد null برمی‌گردد (بدون نوشتن فایل)؛ در محیط بدون
  /// دیالوگ (خطای پلتفرمی) مسیر پیش‌فرض اسناد استفاده می‌شود تا اندروید نشکند.
  static Future<String?> saveToUserPath(Uint8List bytes, String suggestedName) async {
    String? path;
    try {
      final save = await getSaveLocation(
          suggestedName: suggestedName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PDF', extensions: ['pdf'])
          ]);
      path = save?.path;
    } catch (_) {
      // پلتفرم بدون دیالوگ — مسیر پیش‌فرض اسناد
      final dir = await PdfService.receiptsDir();
      path = p.join(dir, suggestedName);
    }
    if (path == null || path.isEmpty) return null; // انصراف کاربر — بدون نوشتن
    final f = File(path);
    await f.writeAsBytes(bytes);
    return path;
  }

  static pw.Widget _cell(String text, pw.Font font, double size) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: size)),
      );
}
