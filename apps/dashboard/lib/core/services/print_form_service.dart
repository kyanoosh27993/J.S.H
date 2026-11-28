/// تنظیمات فرم‌ها و چاپ (v0.14.0) — طراح قالب PDF با جانمایی آزاد اجزا
///
/// قالب هر فرم (پذیرش / پیش‌فاکتور / فاکتور قطعی) به‌صورت JSON در تنظیمات
/// ذخیره می‌شود؛ هر جزء با مختصات درصدی (نسبت به صفحه) جانمایی می‌شود تا
/// خروجی پرینت دقیقاً مطابق دلخواه کاربر باشد:
///  - text: متن تایپی آزاد (تعهدات، سربرگ و هر متن دیگر) با اندازه/بولد/چینش
///  - field: یکی از ریز اقلام برنامه (کد سفارش، نام مشتری، تاریخ، مبلغ و …)
///  - items_table: جدول اقلام (اقلام مصرفی/خدمات فاکتور یا لوازم پذیرش)
///    با انتخاب ستون‌ها (شرح، تعداد، قیمت واحد، جمع)
///  - logo / stamp / sign_seller: تصاویر فروشگاه (بند ۶)
///  - sign_customer: کادر خالی امضای مشتری
///  - qr: کد QR سفارش — totals: جمع/تخفیف/خالص فاکتور
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/db.dart';
import '../models.dart';
import '../repos.dart';
import '../utils.dart';
import 'pdf_service.dart';
import 'shop_settings_service.dart';

// ── مدل جزء قالب ──
class PrintBlock {
  String id;
  String type; // text|field|items_table|logo|stamp|sign_seller|sign_customer|qr|totals
  double x, y, w, h; // درصد نسبت به عرض/ارتفاع صفحه
  double fontSize;
  bool bold;
  String align; // right|center|left
  String value; // متن تایپی یا توکن فیلد {…} — چندخطی مجاز
  String columns; // برای items_table — مانند 'desc,qty,price,total'
  String tableTitle;

  PrintBlock({
    required this.id,
    required this.type,
    this.x = 5,
    this.y = 5,
    this.w = 40,
    this.h = 4,
    this.fontSize = 11,
    this.bold = false,
    this.align = 'right',
    this.value = '',
    this.columns = 'desc,qty,price,total',
    this.tableTitle = '',
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'fontSize': fontSize,
        'bold': bold,
        'align': align,
        'value': value,
        'columns': columns,
        'tableTitle': tableTitle,
      };

  static PrintBlock fromJson(Map<String, Object?> m) => PrintBlock(
        id: (m['id'] ?? '') as String,
        type: (m['type'] ?? 'text') as String,
        x: (m['x'] as num?)?.toDouble() ?? 5,
        y: (m['y'] as num?)?.toDouble() ?? 5,
        w: (m['w'] as num?)?.toDouble() ?? 40,
        h: (m['h'] as num?)?.toDouble() ?? 4,
        fontSize: (m['fontSize'] as num?)?.toDouble() ?? 11,
        bold: (m['bold'] ?? false) as bool,
        align: (m['align'] ?? 'right') as String,
        value: (m['value'] ?? '') as String,
        columns: (m['columns'] ?? 'desc,qty,price,total') as String,
        tableTitle: (m['tableTitle'] ?? '') as String,
      );
}

// ── مدل قالب ──
class PrintFormTemplate {
  final String formKey; // intake | invoice_pre | invoice_final
  String page; // a4 | a5
  List<double> margins; // میلی‌متر: [بالا، پایین، چپ، راست]
  List<PrintBlock> blocks;

  PrintFormTemplate({
    required this.formKey,
    this.page = 'a4',
    List<double>? margins,
    List<PrintBlock>? blocks,
  })  : margins = margins ?? [10, 10, 10, 10],
        blocks = blocks ?? [];

  Map<String, Object?> toJson() => {
        'formKey': formKey,
        'page': page,
        'margins': margins,
        'blocks': [for (final b in blocks) b.toJson()],
      };

  static PrintFormTemplate fromJson(Map<String, Object?> m) => PrintFormTemplate(
        formKey: (m['formKey'] ?? '') as String,
        page: (m['page'] ?? 'a4') as String,
        margins: [
          for (final v in ((m['margins'] ?? const []) as List)) (v as num).toDouble()
        ],
        blocks: [
          for (final b in ((m['blocks'] ?? const []) as List))
            PrintBlock.fromJson((b as Map).cast<String, Object?>()),
        ],
      );
}

// ── سرویس ──
class PrintFormService {
  /// نام فرم‌ها برای انتخاب در طراح
  static const Map<String, String> forms = {
    'intake': 'رسید پذیرش',
    'invoice_pre': 'پیش‌فاکتور',
    'invoice_final': 'فاکتور قطعی',
  };

  static const _settingsKey = 'print_form_templates';

  /// کاتالوگ ریز اقلام قابل درج به تفکیک فرم — توکن → برچسب فارسی
  static const Map<String, Map<String, String>> fieldCatalog = {
    'intake': {
      '{code}': 'کد سفارش',
      '{customer_name}': 'نام مشتری',
      '{phone}': 'تلفن مشتری',
      '{national_id}': 'کد ملی',
      '{device_model}': 'مدل دستگاه',
      '{serial}': 'شماره سریال / IMEI',
      '{defect}': 'عیب اعلامی',
      '{device_state}': 'وضعیت ظاهری کالا',
      '{intake_date}': 'تاریخ پذیرش',
      '{due_date}': 'تاریخ تحویل',
      '{deposit}': 'بیعانه',
      '{tag}': 'برچسب مشتری',
      '{estimate}': 'قیمت احتمالی',
    },
    'invoice_pre': {
      '{invoice_number}': 'شماره سند',
      '{invoice_date}': 'تاریخ صدور',
      '{customer_name}': 'نام مشتری',
      '{phone}': 'تلفن مشتری',
      '{code}': 'کد سفارش',
      '{device_model}': 'مدل دستگاه',
      '{serial}': 'شماره سریال / IMEI',
      '{total}': 'مبلغ کل',
      '{discount}': 'تخفیف',
      '{net}': 'مبلغ نهایی',
    },
    'invoice_final': {
      '{invoice_number}': 'شماره سند',
      '{invoice_date}': 'تاریخ صدور',
      '{customer_name}': 'نام مشتری',
      '{phone}': 'تلفن مشتری',
      '{code}': 'کد سفارش',
      '{device_model}': 'مدل دستگاه',
      '{serial}': 'شماره سریال / IMEI',
      '{total}': 'مبلغ کل',
      '{discount}': 'تخفیف',
      '{net}': 'مبلغ نهایی',
    },
  };

  /// برچسب انواع جزء — برای افزودن در طراح
  static const Map<String, String> blockTypeLabels = {
    'text': 'متن تایپی (تعهدات/سربرگ…)',
    'field': 'فیلد برنامه (توکن {…})',
    'items_table': 'جدول اقلام',
    'logo': 'لوگو',
    'stamp': 'مهر فروشگاه',
    'sign_seller': 'امضای فروشنده (تصویر)',
    'sign_customer': 'کادر امضای مشتری',
    'qr': 'کد QR سفارش',
    'totals': 'جمع/تخفیف/خالص',
  };

  static Future<Map<String, Object?>> _readAll() async {
    try {
      final raw = await SettingsRepo.get(_settingsKey, '{}');
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  static Future<PrintFormTemplate?> load(String formKey) async {
    final all = await _readAll();
    final m = all[formKey];
    if (m == null) return null;
    try {
      return PrintFormTemplate.fromJson((m as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists(String formKey) async =>
      (await load(formKey)) != null;

  static Future<void> save(PrintFormTemplate t) async {
    final all = await _readAll();
    all[t.formKey] = t.toJson();
    await SettingsRepo.set(_settingsKey, jsonEncode(all));
  }

  static Future<void> remove(String formKey) async {
    final all = await _readAll();
    all.remove(formKey);
    await SettingsRepo.set(_settingsKey, jsonEncode(all));
  }

  // ═══ رندر PDF از قالب ═══
  /// [data] نگاشت توکن → مقدار نهایی؛ [items] سطرهای جدول اقلام؛
  /// [signatureBytes] امضای ثبت‌شده پذیرش (اختیاری — جایگزین کادر می‌شود)
  static Future<String> build({
    required PrintFormTemplate t,
    required Map<String, String> data,
    List<List<String>> items = const [],
    String tableTitle = '',
    Uint8List? signatureBytes,
  }) async {
    await PdfService.ensureFonts();
    final logo = await ShopSettingsService.bytesOf(ShopImage.logo);
    final stamp = await ShopSettingsService.bytesOf(ShopImage.stamp);
    final seller = await ShopSettingsService.bytesOf(ShopImage.signature);

    pw.MemoryImage? logoImg;
    pw.MemoryImage? stampImg;
    pw.MemoryImage? sellerImg;
    pw.MemoryImage? custImg;
    try {
      if (logo != null && logo.isNotEmpty) {
        logoImg = pw.MemoryImage(Uint8List.fromList(logo));
      }
      if (stamp != null && stamp.isNotEmpty) {
        stampImg = pw.MemoryImage(Uint8List.fromList(stamp));
      }
      if (seller != null && seller.isNotEmpty) {
        sellerImg = pw.MemoryImage(Uint8List.fromList(seller));
      }
      if (signatureBytes != null && signatureBytes.isNotEmpty) {
        custImg = pw.MemoryImage(signatureBytes);
      }
    } catch (_) {}

    final pageFormat = t.page == 'a5' ? PdfPageFormat.a5 : PdfPageFormat.a4;
    final m = t.margins;
    final doc = pw.Document();

    pw.Widget imageFor(PrintBlock b) {
      final pw.MemoryImage? img = switch (b.type) {
        'logo' => logoImg,
        'stamp' => stampImg,
        'sign_seller' => sellerImg,
        _ => null,
      };
      if (img == null) {
        return pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text('(تصویر ${blockTypeLabels[b.type] ?? b.type} ثبت نشده)',
              style: pw.TextStyle(
                  font: PdfService.regularFont,
                  fontSize: 8,
                  color: PdfColors.grey600)),
        );
      }
      return pw.Image(img, fit: pw.BoxFit.contain);
    }

    pw.Widget boxFor(PrintBlock b) {
      final size = b.fontSize;
      final font = b.bold ? PdfService.boldFont : PdfService.regularFont;
      final align = switch (b.align) {
        'center' => pw.TextAlign.center,
        'left' => pw.TextAlign.left,
        _ => pw.TextAlign.right,
      };
      switch (b.type) {
        case 'logo':
        case 'stamp':
        case 'sign_seller':
          return imageFor(b);
        case 'sign_customer':
          return custImg != null
              ? pw.Image(custImg, fit: pw.BoxFit.contain)
              : pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
                  ),
                  alignment: pw.Alignment.bottomCenter,
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Text('امضای مشتری',
                      style: pw.TextStyle(
                          font: PdfService.regularFont,
                          fontSize: size - 1,
                          color: PdfColors.grey600)),
                );
        case 'qr':
          final code = data['{code}'] ?? '';
          if (code.isEmpty) return pw.SizedBox();
          return pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: code,
            color: PdfColors.black,
          );
        case 'text':
          return pw.Text(b.value,
              textAlign: align,
              style: pw.TextStyle(
                  font: font, fontSize: size, lineSpacing: size * 0.6));
        case 'field':
          final resolved = data[b.value] ?? '';
          return pw.Text(resolved,
              textAlign: align,
              style: pw.TextStyle(font: font, fontSize: size));
        case 'totals':
          final lines = <pw.Widget>[];
          pw.Widget line(String l, String v) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(l,
                      style: pw.TextStyle(font: PdfService.boldFont, fontSize: size)),
                  pw.Text(v,
                      style: pw.TextStyle(font: font, fontSize: size)),
                ],
              );
          if ((data['{total}'] ?? '').isNotEmpty) {
            lines.add(line('جمع کل', data['{total}']!));
          }
          if ((data['{discount}'] ?? '').isNotEmpty) {
            lines.add(line('تخفیف', data['{discount}']!));
          }
          if ((data['{net}'] ?? '').isNotEmpty) {
            lines.add(line('مبلغ نهایی', data['{net}']!));
          }
          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: lines);
        case 'items_table':
          // ستون‌ها بر اساس انتخاب کاربر
          final cols = b.columns.split(',');
          final widths = <pw.TableColumnWidth>[];
          final headers = <pw.Widget>[];
          final labels = {
            'desc': 'شرح',
            'qty': 'تعداد',
            'price': 'قیمت واحد',
            'total': 'جمع',
            'type': 'نوع',
          };
          final n = cols.length;
          for (var i = 0; i < n; i++) {
            final c = cols[i].trim();
            final flexible = c == 'desc';
            widths.add(flexible
                ? const pw.FlexColumnWidth(3)
                : const pw.FlexColumnWidth(1));
            headers.add(pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text(labels[c] ?? c,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: PdfService.boldFont, fontSize: size)),
            ));
          }
          final rows = <pw.TableRow>[
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: headers,
            ),
            for (final r in items)
              pw.TableRow(
                children: [
                  for (final c in cols)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(
                          switch (c.trim()) {
                            'qty' => toPersianDigits(r[1]),
                            'price' => moneyToman(int.tryParse(r[2]) ?? 0),
                            'total' => moneyToman(int.tryParse(r[3]) ?? 0),
                            'type' => r.length > 4 ? r[4] : '',
                            _ => r[0],
                          },
                          textAlign: c.trim() == 'desc'
                              ? pw.TextAlign.right
                              : pw.TextAlign.center,
                          style: pw.TextStyle(
                              font: PdfService.regularFont, fontSize: size - 0.5)),
                    ),
                ],
              ),
          ];
          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (b.tableTitle.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Text(b.tableTitle,
                        style: pw.TextStyle(
                            font: PdfService.boldFont, fontSize: size)),
                  ),
                pw.Table(
                  border: pw.TableBorder.all(
                      color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    for (var i = 0; i < widths.length; i++) i: widths[i],
                  },
                  children: rows,
                ),
              ]);
        default:
          return pw.SizedBox();
      }
    }

    final stackChildren = <pw.Widget>[];
    for (final b in t.blocks) {
      stackChildren.add(pw.Positioned(
        left: b.x / 100 * pageFormat.width,
        top: b.y / 100 * pageFormat.height,
        child: pw.SizedBox(
          width: b.w / 100 * pageFormat.width,
          height: b.h / 100 * pageFormat.height,
          child: boxFor(b),
        ),
      ));
    }

    doc.addPage(pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.fromLTRB(m[2], m[0], m[3], m[1]),
      build: (ctx) => pw.Stack(children: stackChildren),
    ));

    final dir = await PdfService.receiptsDir();
    await Directory(dir).create(recursive: true);
    final path =
        '$dir/print_${t.formKey}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  /// داده‌های واقعی یک سفارش/فاکتور برای رندر
  static Future<Map<String, String>> intakeData({
    required Ticket ticket,
    required Customer customer,
    required Device device,
    Map<String, String> shop = const {},
  }) async {
    return {
      '{code}': ticket.code,
      '{customer_name}': customer.name,
      '{phone}': customer.phone,
      '{national_id}': customer.nationalId,
      '{device_model}': device.model,
      '{serial}': device.serial,
      '{defect}': ticket.defect,
      '{device_state}': ticket.phoneState,
      '{intake_date}': shamsiDate(ticket.intakeDate),
      '{due_date}': shamsiDate(ticket.dueDate),
      '{deposit}': ticket.depositAmount > 0
          ? moneyToman(ticket.depositAmount)
          : '—',
      '{tag}': customer.tag,
      '{estimate}': ticket.estimateAmount > 0
          ? moneyToman(ticket.estimateAmount)
          : '—',
    };
  }

  /// اقلام پذیرش — لیست لوازم همراه
  static List<List<String>> accessoriesRows(Ticket t) => [
        for (final a in t.accessories) [a],
      ];

  /// اقلام فاکتور — از ticket_items
  static Future<List<List<String>>> invoiceItemsRows(int ticketId) async {
    final rows = <List<String>>[];
    try {
      for (final it in await TicketItemRepo.byTicket(ticketId)) {
        final desc = it.description;
        final kindFa = it.type == 'piece'
            ? 'قطعه'
            : it.type == 'discount'
                ? 'تخفیف'
                : it.type == 'damage'
                    ? 'خسارت'
                    : (it.kind == 'part' ? 'قطعه' : 'خدمات');
        rows.add([
          desc,
          '${it.qty}',
          '${it.price}',
          '${it.qty * it.price}',
          kindFa,
        ]);
      }
    } catch (_) {}
    return rows;
  }

  /// داده فاکتور — از ردیف invoices
  static Future<Map<String, String>> invoiceData({
    required Map<String, Object?> inv,
    required Ticket ticket,
    required Customer customer,
    required Device device,
  }) async {
    final total = (inv['total'] ?? 0) as int;
    final disc = (inv['discount'] ?? 0) as int;
    final issued = DateTime.tryParse((inv['issued_at'] ?? '') as String);
    return {
      '{invoice_number}': (inv['number'] ?? '') as String,
      '{invoice_date}':
          issued == null ? '' : shamsiDate(issued),
      '{customer_name}': customer.name,
      '{phone}': customer.phone,
      '{code}': ticket.code,
      '{device_model}': device.model,
      '{serial}': device.serial,
      '{total}': moneyToman(total),
      '{discount}': disc > 0 ? moneyToman(disc) : '—',
      '{net}': moneyToman(total),
    };
  }
}
