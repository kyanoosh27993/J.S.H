/// جدول پیشرفته — قاعده جدول‌ها (نسخه ۰.۳)
/// سورت هر سربرگ + جستجو + فیلتر هر ستون + مخفی/نمایش ستون‌ها + تغییر عرض ستون‌ها
/// + ارتفاع سطر از چگالی تم + جمع پویای ستون‌های عددی بر اساس فیلترها
/// + پایدارسازی چیدمان هر جدول (عرض/مخفی) در تنظیمات
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/repos.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import 'app_text.dart';

class ProColumn<T> {
  final String label;
  final String Function(T) display;
  final num? Function(T)? numeric;
  final bool filterable;
  final double width;
  const ProColumn({
    required this.label,
    required this.display,
    this.numeric,
    this.filterable = false,
    this.width = 130,
  });
}

class DataTablePro<T> extends StatefulWidget {
  final List<T> rows;
  final List<ProColumn<T>> columns;
  final String tableId; // برای پایدارسازی چیدمان
  final String Function(T)? searchIndex;
  final Widget Function(T)? rowAction;
  final void Function(T)? onRowTap;
  final String sumLabel;
  final bool showSums;

  const DataTablePro({
    super.key,
    required this.rows,
    required this.columns,
    required this.tableId,
    this.searchIndex,
    this.rowAction,
    this.onRowTap,
    this.sumLabel = 'جمع',
    this.showSums = true,
  });

  @override
  State<DataTablePro<T>> createState() => _DataTableProState<T>();
}

class _DataTableProState<T> extends State<DataTablePro<T>> {
  String query = '';
  int sortCol = 0;
  bool asc = true; // پیش‌فرض صعودی — قاعده ۶
  final Set<String> filters = {}; // «ستون==مقدار»
  final Set<String> hidden = {};
  final Map<String, double> widths = {};
  bool loaded = false;
  int? openFilterCol;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    try {
      final raw = await SettingsRepo.get('table_cfg_${widget.tableId}');
      if (raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          hidden.addAll((j['hidden'] as List? ?? []).cast<String>());
          (j['widths'] as Map? ?? {}).forEach((k, v) {
            widths[k as String] = (v as num).toDouble();
          });
        });
      }
    } catch (_) {}
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _saveLayout() async {
    try {
      await SettingsRepo.set(
        'table_cfg_${widget.tableId}',
        jsonEncode({'hidden': hidden.toList(), 'widths': widths}),
      );
    } catch (_) {}
  }

  double _w(int i) => widths[widget.columns[i].label] ?? widget.columns[i].width;

  List<T> get _filtered {
    var out = widget.rows;
    final searchFn = widget.searchIndex;
    if (query.isNotEmpty && searchFn != null) {
      final q = query.trim();
      out = out.where((r) {
        final idx = searchFn(r);
        return idx.contains(q) || idx.contains(toEnglishDigits(q));
      }).toList();
    }
    if (filters.isNotEmpty) {
      out = out.where((r) {
        for (final f in filters) {
          final i = f.indexOf('==');
          final col = widget.columns.firstWhere((c) => c.label == f.substring(0, i),
              orElse: () => widget.columns.first);
          if (col.display(r) != f.substring(i + 2)) return false;
        }
        return true;
      }).toList();
    }
    return out;
  }

  List<T> get _sorted {
    final out = [..._filtered];
    final col = widget.columns[sortCol];
    out.sort((a, b) {
      final na = col.numeric?.call(a);
      final nb = col.numeric?.call(b);
      int cmp;
      if (na != null && nb != null) {
        cmp = na.compareTo(nb);
      } else {
        cmp = col.display(a).compareTo(col.display(b));
      }
      return asc ? cmp : -cmp;
    });
    return out;
  }

  Set<String> _uniqueValues(ProColumn<T> col) {
    final s = <String>{};
    for (final r in widget.rows) {
      s.add(col.display(r));
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final rowH = 44.0 * cfg.density;
    final visibleIdx = [
      for (var i = 0; i < widget.columns.length; i++)
        if (!hidden.contains(widget.columns[i].label)) i,
    ];
    final data = _sorted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // نوار ابزار: جستجو + نمایش/مخفی ستون‌ها + پاک‌سازی فیلترها
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  hintText: 'جستجو در جدول...',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'نمایش/مخفی ستون‌ها',
              icon: Icon(Icons.view_column, size: 20, color: p.textSecondary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(cfg.baseRadius * 0.8)),
              onSelected: (_) {},
              itemBuilder: (_) => [
                for (final c in widget.columns)
                  CheckedPopupMenuItem(
                    checked: !hidden.contains(c.label),
                    value: c.label,
                    onTap: () => setState(() {
                      if (hidden.contains(c.label)) {
                        hidden.remove(c.label);
                      } else if (visibleIdx.length > 1) {
                        hidden.add(c.label);
                      }
                      _saveLayout();
                    }),
                    child: AppText(c.label, style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
            if (filters.isNotEmpty)
              IconButton(
                tooltip: 'پاک‌سازی همه فیلترها',
                icon: Badge(
                  label: AppNumText(toPersianDigits('${filters.length}')),
                  child: Icon(Icons.filter_alt, size: 20,
                      color: p.primary),
                ),
                onPressed: () => setState(() => filters.clear()),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // جدول با اسکرول افقی — هیچ چیز از صفحه بیرون نمی‌زند
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(visibleIdx, cfg, p),
                    ...data.map((r) => _row(visibleIdx, r, rowH, cfg, p)),
                    if (widget.showSums) _sumRow(visibleIdx, data, cfg, p),
                  ],
                ),
              ),
            ),
            if (openFilterCol != null)
              Positioned(
                top: 38,
                left: 0,
                child: _filterPanel(openFilterCol!, cfg, p),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            AppText(
              '${toPersianDigits('${data.length}')} ردیف از ${toPersianDigits('${widget.rows.length}')} — «${widget.columns[sortCol].label}» ${asc ? 'صعودی' : 'نزولی'}',
              style: TextStyle(fontSize: 11, color: p.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  // ── سربرگ ──
  Widget _header(List<int> visibleIdx, ThemeConfig cfg, ThemePalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: p.primary.withValues(alpha: 0.5), width: 1.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final i in visibleIdx)
            _headerCell(i, cfg, p),
          if (widget.rowAction != null)
            const SizedBox(width: 62, height: 40),
        ],
      ),
    );
  }

  Widget _headerCell(int i, ThemeConfig cfg, ThemePalette p) {
    final col = widget.columns[i];
    final w = _w(i);
    final isSorted = sortCol == i;
    final hasFilter = filters.any((f) => f.startsWith('${col.label}=='));
    final filterOpen = openFilterCol == i;

    return SizedBox(
      width: w,
      height: 40,
      child: Row(
        children: [
          // سورت با کلیک روی عنوان
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                if (isSorted) {
                  asc = !asc;
                } else {
                  sortCol = i;
                  asc = true;
                }
              }),
              hoverColor: p.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(col.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: isSorted ? p.primary : p.textPrimary,
                          )),
                    ),
                    AnimatedRotation(
                      turns: isSorted && !asc ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        isSorted ? Icons.arrow_upward : Icons.unfold_more,
                        size: 13,
                        color: isSorted ? p.primary : p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // فیلتر ستون
          if (col.filterable)
            GestureDetector(
              onTap: () =>
                  setState(() => openFilterCol = filterOpen ? null : i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(
                  hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                  size: 14.5,
                  color: hasFilter ? p.primary : p.textSecondary,
                ),
              ),
            ),
          // دستگیره تغییر عرض ستون
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                setState(() {
                  widths[col.label] =
                      (widths[col.label] ?? col.width) + d.delta.dx;
                  widths[col.label] =
                      widths[col.label]!.clamp(64.0, 620.0);
                });
              },
              onHorizontalDragEnd: (_) => _saveLayout(),
              child: SizedBox(
                width: 8,
                height: 40,
                child: Center(
                  child: Container(
                    width: 2.5,
                    height: 16,
                    decoration: BoxDecoration(
                      color: p.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── پاپ‌آپ فیلتر مقادیر ستون ──
  Widget _filterPanel(int i, ThemeConfig cfg, ThemePalette p) {
    final col = widget.columns[i];
    final values = _uniqueValues(col).toList()..sort();
    final selected = filters
        .where((f) => f.startsWith('${col.label}=='))
        .map((f) => f.substring(f.indexOf('==') + 2))
        .toSet();
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(cfg.baseRadius * 0.8),
        color: p.surface,
        child: Container(
          width: 240,
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(cfg.baseRadius * 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: AppText('فیلتر «${col.label}»',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: p.primary)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final v in values.take(40))
                        CheckboxListTile(
                          dense: true,
                          value: selected.isEmpty || selected.contains(v),
                          title: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(v, style: const TextStyle(fontSize: 12)),
                          ),
                          onChanged: (on) {
                            setState(() {
                              filters.remove('${col.label}==$v');
                              if (on == true) {
                                filters.add('${col.label}==$v');
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          filters.removeWhere((f) => f.startsWith('${col.label}=='));
                          openFilterCol = null;
                        });
                      },
                      child: const Text('حذف فیلتر', style: TextStyle(fontSize: 12)),
                    ),
                    FilledButton(
                      onPressed: () => setState(() => openFilterCol = null),
                      child: const Text('اعمال', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ردیف داده ──
  Widget _row(List<int> visibleIdx, T row, double rowH, ThemeConfig cfg,
      ThemePalette p) {
    return InkWell(
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      hoverColor: p.primary.withValues(alpha: 0.06),
      child: Container(
        height: rowH,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border, width: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in visibleIdx)
              SizedBox(
                width: _w(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  // shrink-to-fit — هیچ متنی بیرون نمی‌زند
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: widget.columns[i].numeric != null
                        ? AppNumText(widget.columns[i].display(row),
                            style: const TextStyle(fontSize: 12.5))
                        : Text(widget.columns[i].display(row),
                            style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ),
            if (widget.rowAction != null)
              SizedBox(width: 62, child: widget.rowAction!(row)),
          ],
        ),
      ),
    );
  }

  // ── ردیف جمع پویا ──
  Widget _sumRow(List<int> visibleIdx, List<T> data, ThemeConfig cfg,
      ThemePalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final i in visibleIdx)
            SizedBox(
              width: _w(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AppNumText(_sumCell(widget.columns[i], data, cfg, p),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: p.textPrimary)),
                ),
              ),
            ),
          if (widget.rowAction != null) const SizedBox(width: 62),
        ],
      ),
    );
  }

  String _sumCell(ProColumn<T> col, List<T> data, ThemeConfig cfg,
      ThemePalette p) {
    if (col.numeric == null) {
      final isSort = widget.columns[sortCol].label == col.label;
      return '${widget.sumLabel}${isSort ? ' ⬇' : ''}';
    }
    var sum = 0.0;
    for (final r in data) {
      final v = col.numeric!.call(r);
      if (v != null) sum += v;
    }
    return sum == sum.roundToDouble()
        ? money(sum.round())
        : toPersianDigits(sum.toStringAsFixed(1));
  }
}
