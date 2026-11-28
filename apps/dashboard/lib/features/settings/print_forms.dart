/// طراح قالب چاپ (v0.14.0) — صفحه «تنظیمات فرم‌ها و چاپ»
///
/// سه تب کاری مثل ورد:
///  ۱) سربرگ و متن‌ها — تایپ آزاد (تعهدات، سربرگ، متن‌های دیگر) با
///     اندازه فونت/بولد/چینش؛ هر متن یک جزء قابل‌جانمایی است
///  ۲) بوم جانمایی — پیش‌نمایش صفحه با درگ‌کردن اجزا (لوگو، مهر، امضاها،
///     تاریخ، فیلدها، جدول اقلام) و پنل مشخصات جزء انتخاب‌شده
///  ۳) اقلام جدول — انتخاب اینکه کدام لیست‌ها کجا چاپ شوند و چه ستون‌هایی داشته باشند
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/print_form_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/attach_service.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';

class PrintFormsPage extends StatefulWidget {
  const PrintFormsPage({super.key});
  @override
  State<PrintFormsPage> createState() => _PrintFormsPageState();
}

class _PrintFormsPageState extends State<PrintFormsPage> {
  String formKey = 'invoice_final';
  PrintFormTemplate? t;
  bool loading = true;
  String? selectedId;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final tpl = await PrintFormService.load(formKey);
    if (!mounted) return;
    setState(() {
      t = tpl;
      loading = false;
      selectedId = null;
    });
  }

  Future<void> _save() async {
    if (t == null) return;
    await PrintFormService.save(t!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('قالب چاپ ذخیره شد')));
  }

  PrintBlock? get _sel {
    if (t == null || selectedId == null) return null;
    for (final b in t!.blocks) {
      if (b.id == selectedId) return b;
    }
    return null;
  }

  void _touch() => setState(() {});

  void _addBlock(String type) {
    if (t == null) return;
    final b = PrintBlock(
      id: 'b${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      y: (5 + t!.blocks.length * 4) % 90,
      value: type == 'field'
          ? PrintFormService.fieldCatalog[formKey]!.keys.first
          : '',
    );
    setState(() {
      t!.blocks.add(b);
      selectedId = b.id;
    });
  }

  void _deleteSelected() {
    if (t == null || selectedId == null) return;
    setState(() {
      t!.blocks.removeWhere((b) => b.id == selectedId);
      selectedId = null;
    });
  }

  // ── چاپ آزمایشی با داده نمونه ──
  Future<void> _testPrint() async {
    if (t == null) return;
    try {
      final sample = <String, String>{
        for (final k in PrintFormService.fieldCatalog[formKey]!.keys)
          k: 'نمونه ${k.replaceAll('{', '').replaceAll('}', '')}',
      };
      final items = <List<String>>[
        ['تغییر تاچ ال سی دی آیفون ۱۲', '1', '2500000', '2500000', 'قطعه'],
        ['خدمات نرم‌افزاری', '1', '500000', '500000', 'خدمات'],
        ['درب پشت', '', '', '', 'لوازم'],
      ];
      final path = await PrintFormService.build(
        t: t!,
        data: sample,
        items: formKey == 'intake' ? [items[2]] : items,
        tableTitle: formKey == 'intake' ? 'لوازم همراه دستگاه' : 'اقلام فاکتور',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF آزمایشی ساخته شد: ${toPersianDigits(path)}')));
      await AttachService.openSystem(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطا در ساخت PDF: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DefaultTabController(
        length: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.design_services, size: 20),
            const SizedBox(width: 8),
            AppText('تنظیمات فرم‌ها و چاپ',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: p.textPrimary)),
            const SizedBox(width: 16),
            // انتخاب فرم
            DropdownButton<String>(
              value: formKey,
              items: [
                for (final e in PrintFormService.forms.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                if (v == null || v == formKey) return;
                formKey = v;
                _load();
              },
              underline: const SizedBox(),
            ),
            const SizedBox(width: 12),
            if (t == null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    t = PrintFormTemplate(formKey: formKey);
                  });
                },
                icon: const Icon(Icons.add, size: 17),
                label: const Text('ساخت قالب جدید'),
              ),
            if (t != null) ...[
              const Spacer(),
              TextButton.icon(
                onPressed: _testPrint,
                icon: const Icon(Icons.picture_as_pdf, size: 17),
                label: const Text('چاپ آزمایشی'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await PrintFormService.remove(formKey);
                  _load();
                },
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('حذف قالب'),
              ),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, size: 17),
                label: const Text('ذخیره قالب'),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          if (t == null)
            Expanded(
              child: Center(
                child: AppText(
                    'برای این فرم هنوز قالبی ساخته نشده — با «ساخت قالب جدید» شروع کنید',
                    style: TextStyle(fontSize: 13, color: p.textSecondary)),
              ),
            )
          else ...[
            TabBar(
              onTap: (i) => _touch(),
              tabs: const [
                Tab(text: '۱ — سربرگ و متن‌ها'),
                Tab(text: '۲ — بوم جانمایی'),
                Tab(text: '۳ — اقلام جدول‌ها'),
              ],
              labelColor: p.textPrimary,
            ),
            Expanded(
              child: TabBarView(children: [
                _textsTab(cfg),
                _canvasTab(cfg),
                _tablesTab(cfg),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  // ═══ تب ۱ — سربرگ و متن‌ها ═══
  Widget _textsTab(ThemeConfig cfg) {
    final p = cfg.palette;
    final texts = t!.blocks.where((b) => b.type == 'text').toList();
    return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: [
      Row(children: [
        OutlinedButton.icon(
          onPressed: () => _addBlock('text'),
          icon: const Icon(Icons.post_add, size: 17),
          label: const Text('متن جدید (تعهدات، سربرگ، یادداشت…)'),
        ),
        const SizedBox(width: 10),
        AppText(
            'هر متن بعد از افزودن در تب «بوم جانمایی» با درگ به محل دلخواه منتقل می‌شود',
            style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
      ]),
      const SizedBox(height: 10),
      for (final b in texts)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      selectedId = b.id;
                      tab = 1;
                    });
                  },
                  icon: const Icon(Icons.open_with, size: 16),
                  label: const Text('جانمایی در بوم'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () {
                    setState(() {
                      t!.blocks.remove(b);
                      if (selectedId == b.id) selectedId = null;
                    });
                  },
                ),
              ]),
              TextField(
                controller: TextEditingController(text: b.value)
                  ..selection = TextSelection.collapsed(
                      offset: b.value.length),
                maxLines: 6,
                style: TextStyle(
                    fontSize: b.fontSize,
                    fontWeight:
                        b.bold ? FontWeight.bold : FontWeight.normal),
                decoration: const InputDecoration(
                    labelText: 'متن — چند خطی (تایپ آزاد مانند ورد)'),
                onChanged: (v) => b.value = v,
              ),
              const SizedBox(height: 8),
              _propsRow(b, cfg),
            ]),
          ),
        ),
      // فیلدهای برنامه — افزودن سریع به‌عنوان جزء
      Row(children: [
        OutlinedButton.icon(
          onPressed: () => _addBlock('field'),
          icon: const Icon(Icons.data_object, size: 17),
          label: const Text('افزودن فیلد برنامه (تاریخ، نام مشتری، شماره سند…)'),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final e in PrintFormService.fieldCatalog[formKey]!.entries)
            InputChip(
              label: Text('${e.value}  ${e.key}',
                  style: const TextStyle(fontSize: 10.5)),
              onPressed: () {
                final b = PrintBlock(
                  id: 'f${DateTime.now().millisecondsSinceEpoch}',
                  type: 'field',
                  value: e.key,
                  y: (10 + t!.blocks.length * 4) % 90,
                );
                setState(() {
                  t!.blocks.add(b);
                  selectedId = b.id;
                });
              },
            ),
        ],
      ),
    ]);
  }

  // ═══ تب ۲ — بوم جانمایی ═══
  Widget _canvasTab(ThemeConfig cfg) {
    final p = cfg.palette;
    final isA5 = t!.page == 'a5';
    const pageW = 360.0;
    final pageH = pageW * (isA5 ? 210 / 148 : 297 / 210);
    final sel = _sel;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(10), children: [
          Row(children: [
            AppText('اندازه کاغذ:',
                style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'a4', label: Text('A4')),
                ButtonSegment(value: 'a5', label: Text('A5')),
              ],
              selected: {t!.page},
              onSelectionChanged: (v) {
                setState(() => t!.page = v.first);
              },
            ),
            const SizedBox(width: 16),
            AppText('حاشیه (میلی‌متر):',
                style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
            const SizedBox(width: 8),
            _marginField(0, 'بالا'),
            _marginField(1, 'پایین'),
            _marginField(2, 'چپ'),
            _marginField(3, 'راست'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _addBlock('logo'),
              icon: const Icon(Icons.image, size: 17),
              label: const Text('لوگو'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _addBlock('stamp'),
              icon: const Icon(Icons.approval, size: 17),
              label: const Text('مهر'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _addBlock('sign_seller'),
              icon: const Icon(Icons.draw, size: 17),
              label: const Text('امضای فروشنده'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _addBlock('sign_customer'),
              icon: const Icon(Icons.pan_tool, size: 17),
              label: const Text('امضای مشتری'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _addBlock('qr'),
              icon: const Icon(Icons.qr_code, size: 17),
              label: const Text('QR'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _addBlock('items_table'),
              icon: const Icon(Icons.table_rows, size: 17),
              label: const Text('جدول اقلام'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _addBlock('totals'),
              icon: const Icon(Icons.calculate, size: 17),
              label: const Text('جمع/تخفیف/خالص'),
            ),
          ]),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: pageW,
              height: pageH,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Stack(clipBehavior: Clip.none, children: [
                for (final b in t!.blocks)
                  Positioned(
                    left: b.x / 100 * pageW,
                    top: b.y / 100 * pageH,
                    child: GestureDetector(
                      onTap: () => setState(() => selectedId = b.id),
                      onPanUpdate: (d) {
                        setState(() {
                          b.x = (b.x + d.delta.dx / pageW * 100)
                              .clamp(0.0, 100.0);
                          b.y = (b.y + d.delta.dy / pageH * 100)
                              .clamp(0.0, 100.0);
                        });
                      },
                      child: Container(
                        width: b.w / 100 * pageW,
                        height: b.h / 100 * pageH,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: selectedId == b.id
                                  ? Colors.blue
                                  : Colors.grey.shade400,
                              width: selectedId == b.id ? 1.6 : 0.8),
                          color: selectedId == b.id
                              ? Colors.blue.withValues(alpha: 0.06)
                              : Colors.transparent,
                        ),
                        child: _blockPreview(b, cfg),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          AppText(
              'هر جزء را با کشیدن (درگ) روی بوم به محل دلخواه ببرید؛ برای جزئیات بیشتر آن را انتخاب کنید',
              style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
        ]),
      ),
      // پنل مشخصات جزء انتخاب‌شده
      if (sel != null)
        SizedBox(
          width: 300,
          child: Card(
            margin: const EdgeInsets.all(10),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(children: [
                  Icon(_iconFor(sel.type), size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AppText(
                        PrintFormService.blockTypeLabels[sel.type] ??
                            sel.type,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: _deleteSelected,
                  ),
                ]),
                const Divider(),
                if (sel.type == 'text' || sel.type == 'field') ...[
                  if (sel.type == 'field')
                    DropdownButtonFormField<String>(
                      initialValue: sel.value,
                      items: [
                        for (final e in PrintFormService
                            .fieldCatalog[formKey]!.entries)
                          DropdownMenuItem(
                              value: e.key,
                              child: Text('${e.value} ${e.key}',
                                  style: const TextStyle(fontSize: 12))),
                      ],
                      onChanged: (v) {
                        setState(() => sel.value = v ?? sel.value);
                      },
                      decoration: InputDecoration(
                          labelText: 'کدام فیلد چاپ شود'),
                    ),
                  TextField(
                    controller:
                        TextEditingController(text: sel.value),
                    maxLines: 5,
                    decoration: InputDecoration(
                        labelText: sel.type == 'field'
                            ? 'مقدار ثابت اضافی (اختیاری)'
                            : 'متن'),
                    onChanged: (v) => sel.value = v,
                  ),
                  const SizedBox(height: 8),
                ],
                if (sel.type == 'items_table') ...[
                  TextField(
                    controller:
                        TextEditingController(text: sel.tableTitle),
                    decoration: InputDecoration(
                        labelText: 'عنوان جدول (مانند: اقلام مصرفی)'),
                    onChanged: (v) => sel.tableTitle = v,
                  ),
                  const SizedBox(height: 8),
                ],
                if (sel.type == 'items_table') ...[
                  AppText('ستون‌های جدول:',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 4),
                  _columnToggle('desc', 'شرح'),
                  _columnToggle('qty', 'تعداد'),
                  _columnToggle('price', 'قیمت واحد'),
                  _columnToggle('total', 'جمع'),
                  _columnToggle('type', 'نوع قلم'),
                  const SizedBox(height: 8),
                ],
                _numField('اندازه فونت', sel.fontSize,
                    (v) => sel.fontSize = v),
                CheckboxListTile(
                  dense: true,
                  title: const Text('بولد (درشت)'),
                  value: sel.bold,
                  onChanged: (v) =>
                      setState(() => sel.bold = v ?? false),
                ),
                _alignPicker(sel),
                const SizedBox(height: 4),
                _numField('X — از چپ (%)', sel.x, (v) => sel.x = v),
                _numField('Y — از بالا (%)', sel.y, (v) => sel.y = v),
                _numField('عرض (%)', sel.w, (v) => sel.w = v),
                _numField('ارتفاع (%)', sel.h, (v) => sel.h = v),
              ],
            ),
          ),
        ),
    ]);
  }

  // ═══ تب ۳ — اقلام جدول‌ها ═══
  Widget _tablesTab(ThemeConfig cfg) {
    final p = cfg.palette;
    final tables = t!.blocks.where((b) => b.type == 'items_table').toList();
    return ListView(padding: const EdgeInsets.all(10), children: [
      AppText(
          'در این بخش مشخص می‌کنید چه لیستی (اقلام مصرفی فاکتور، لوازم پذیرش) کجای صفحه چاپ شود و چه ستون‌هایی داشته باشد.',
          style: TextStyle(fontSize: 12.5, color: p.textSecondary, height: 1.7)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => _addBlock('items_table'),
        icon: const Icon(Icons.table_rows, size: 17),
        label: const Text('افزودن جدول اقلام جدید'),
      ),
      const SizedBox(height: 10),
      for (final b in tables)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: TextEditingController(text: b.tableTitle),
                decoration: const InputDecoration(
                    labelText: 'عنوان لیست — مانند «اقلام مصرفی فاکتور»'),
                onChanged: (v) => b.tableTitle = v,
              ),
              const SizedBox(height: 8),
              Wrap(children: [
                _columnToggle('desc', 'شرح'),
                _columnToggle('qty', 'تعداد'),
                _columnToggle('price', 'قیمت واحد'),
                _columnToggle('total', 'جمع'),
                _columnToggle('type', 'نوع قلم'),
              ]),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() => selectedId = b.id),
                icon: const Icon(Icons.open_with, size: 16),
                label: const Text('انتخاب در بوم برای جانمایی'),
              ),
            ]),
          ),
        ),
      AppText(
          'نکته: جدول اقلام فاکتور از «اقلام ثبت‌شده سفارش» و جدول پذیرش از «لوازم همراه» پر می‌شود.',
          style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
    ]);
  }

  // ── ابزارهای کوچک ──
  Widget _columnToggle(String key, String label) {
    final sel = _sel;
    final cols = sel?.columns.split(',') ?? const [];
    final on = cols.contains(key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        selected: on,
        onSelected: (v) {
          setState(() {
            final set = <String>{
              ...sel!.columns.split(',').where((e) => e.isNotEmpty)
            };
            v ? set.add(key) : set.remove(key);
            // ترتیب ثابت
            const order = ['desc', 'qty', 'price', 'total', 'type'];
            sel.columns = order.where(set.contains).join(',');
          });
        },
      ),
    );
  }

  Widget _propsRow(PrintBlock b, ThemeConfig cfg) => Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _numField('اندازه فونت', b.fontSize, (v) => b.fontSize = v,
              width: 110),
          CheckboxListTile(
            dense: true,
            title: const Text('بولد'),
            value: b.bold,
            onChanged: (v) => setState(() => b.bold = v ?? false),
          ),
          _alignPickerInline(b),
        ],
      );

  Widget _alignPicker(PrintBlock b) => _alignPickerInline(b);

  Widget _alignPickerInline(PrintBlock b) => Row(children: [
        const Text('چینش: ', style: TextStyle(fontSize: 12.5)),
        for (final e in const [
            MapEntry('right', 'راست'),
            MapEntry('center', 'وسط'),
            MapEntry('left', 'چپ'),
          ])
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
              selected: b.align == e.key,
              onSelected: (_) => setState(() => b.align = e.key),
            ),
          ),
      ]);

  Widget _numField(String label, double value, void Function(double) onSet,
      {double width = 130}) {
    final ctrl = TextEditingController(text: value.toStringAsFixed(1));
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) {
          final d = double.tryParse(v.replaceAll('٫', '.'));
          if (d != null) onSet(d);
        },
      ),
    );
  }

  Widget _marginField(int i, String label) => SizedBox(
        width: 64,
        child: TextField(
          controller: TextEditingController(
              text: t!.margins[i].toStringAsFixed(0)),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: (v) {
            final d = double.tryParse(v) ?? t!.margins[i];
            if (d >= 0 && d <= 60) t!.margins[i] = d;
          },
        ),
      );

  IconData _iconFor(String type) => switch (type) {
        'logo' => Icons.image,
        'stamp' => Icons.approval,
        'sign_seller' || 'sign_customer' => Icons.draw,
        'qr' => Icons.qr_code,
        'items_table' => Icons.table_rows,
        'totals' => Icons.calculate,
        'field' => Icons.data_object,
        _ => Icons.text_fields,
      };

  // پیش‌نمایش جزء روی بوم
  Widget _blockPreview(PrintBlock b, ThemeConfig cfg) {
    final p = cfg.palette;
    final style = TextStyle(
        fontSize: (b.fontSize * 0.72).clamp(6, 22),
        fontWeight: b.bold ? FontWeight.bold : FontWeight.normal,
        color: Colors.black87);
    final align = switch (b.align) {
      'center' => TextAlign.center,
      'left' => TextAlign.left,
      _ => TextAlign.right,
    };
    switch (b.type) {
      case 'logo':
      case 'stamp':
      case 'sign_seller':
        return const Icon(Icons.image_outlined,
            size: 26, color: Colors.grey);
      case 'sign_customer':
        return Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('امضای مشتری',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
        );
      case 'qr':
        return const Icon(Icons.qr_code_2, size: 28, color: Colors.grey);
      case 'items_table':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (b.tableTitle.isNotEmpty)
            Text(b.tableTitle, style: style, textAlign: align),
          Container(
            height: b.h / 100 * 566,
            decoration:
                BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: Row(children: [
              for (final c in b.columns.split(','))
                Expanded(
                  flex: c.trim() == 'desc' ? 3 : 1,
                  child: Container(
                    decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade300, width: 0.5)),
                    alignment: Alignment.center,
                    child: Text(
                        switch (c.trim()) {
                          'desc' => 'شرح',
                          'qty' => 'تعداد',
                          'price' => 'قیمت',
                          'total' => 'جمع',
                          'type' => 'نوع',
                          _ => c,
                        },
                        style: const TextStyle(fontSize: 8.5)),
                  ),
                ),
            ]),
          ),
        ]);
      case 'totals':
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('جمع کل — مبلغ', style: style, textAlign: align),
          Text('تخفیف — مبلغ', style: style, textAlign: align),
          Text('مبلغ نهایی — مبلغ', style: style, textAlign: align),
        ]);
      case 'field':
        return Text(
            '${PrintFormService.fieldCatalog[formKey]?[b.value] ?? b.value}: مقدار',
            style: style,
            textAlign: align,
            overflow: TextOverflow.ellipsis);
      default:
        return Text(b.value.isEmpty ? 'متن تایپی…' : b.value,
            style: style, textAlign: align);
    }
  }
}
