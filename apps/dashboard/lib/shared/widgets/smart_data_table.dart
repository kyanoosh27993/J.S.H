/// جدول هوشمند گزارش‌ها — قواعد ۴، ۵، ۶
/// سورت سربرگ (صعودی پیش‌فرض) + جستجو + فیلتر ستونی + ردیف جمع + shrink-to-fit + اسکرول افقی موبایل
library;

import 'package:flutter/material.dart';

import '../../core/utils.dart';

class SmartColumn<T> {
  final String label;
  final String Function(T) display;
  final num? Function(T)? numeric;
  final bool filterable;
  final double width;

  const SmartColumn({
    required this.label,
    required this.display,
    this.numeric,
    this.filterable = false,
    this.width = 130,
  });
}

class SmartDataTable<T> extends StatefulWidget {
  final List<T> rows;
  final List<SmartColumn<T>> columns;
  final String Function(T)? searchIndex;
  final Widget Function(T)? rowAction;
  final void Function(T)? onRowTap;
  final String sumLabel;
  final bool showSums;

  const SmartDataTable({
    super.key,
    required this.rows,
    required this.columns,
    this.searchIndex,
    this.rowAction,
    this.onRowTap,
    this.sumLabel = 'جمع',
    this.showSums = true,
  });

  @override
  State<SmartDataTable<T>> createState() => _SmartDataTableState<T>();
}

class _SmartDataTableState<T> extends State<SmartDataTable<T>> {
  String query = '';
  int sortCol = 0;
  bool asc = true; // قاعده ۶: پیش‌فرض صعودی
  String? filterValue;

  List<T> get _filtered {
    var out = widget.rows;
    final searchFn = widget.searchIndex;
    if (query.isNotEmpty && searchFn != null) {
      final q = query.trim();
      out = out.where((r) => searchFn(r).contains(q) ||
          searchFn(r).contains(toEnglishDigits(q))).toList();
    }
    if (filterValue != null) {
      final col = widget.columns[sortCol];
      if (col.filterable) {
        out = out.where((r) => col.display(r) == filterValue).toList();
      }
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

  @override
  Widget build(BuildContext context) {
    final cols = widget.columns;
    final data = _sorted;
    // مقادیر یکتا برای فیلتر ستون فعال
    final filterOptions = <String>{};
    final activeCol = cols[sortCol];
    if (activeCol.filterable) {
      for (final r in widget.rows) {
        filterOptions.add(activeCol.display(r));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // نوار جستجو + فیلتر
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
            if (filterOptions.isNotEmpty && filterOptions.length <= 25)
              DropdownButton<String>(
                hint: const Text('فیلتر', style: TextStyle(fontSize: 12)),
                value: filterValue,
                isDense: true,
                items: [
                  ...filterOptions.map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v, style: const TextStyle(fontSize: 12)),
                      )),
                ],
                onChanged: (v) => setState(() => filterValue = v),
              ),
            if (filterValue != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'حذف فیلتر',
                onPressed: () => setState(() => filterValue = null),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // جدول با اسکرول افقی (قاعده ۴ — موبایل)
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerRow(cols),
                ...data.map((r) => _dataRow(cols, r)),
                if (widget.showSums) _sumRow(cols, data),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${toPersianDigits('${data.length}')} ردیف از ${toPersianDigits('${widget.rows.length}')} — ستون «${cols[sortCol].label}» ${asc ? 'صعودی' : 'نزولی'}',
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
        ),
      ],
    );
  }

  Widget _headerRow(List<SmartColumn<T>> cols) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacitySafe(0.45),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cols.length; i++)
            SizedBox(
              width: cols[i].width,
              child: InkWell(
                onTap: () => setState(() {
                  if (sortCol == i) {
                    asc = !asc;
                  } else {
                    sortCol = i;
                    asc = true; // قاعده ۶: تغییر ستون → صعودی
                  }
                  filterValue = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(cols[i].label,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ),
                      Icon(
                        sortCol == i
                            ? (asc ? Icons.arrow_upward : Icons.arrow_downward)
                            : Icons.unfold_more,
                        size: 13,
                        color: sortCol == i
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.rowAction != null)
            const SizedBox(width: 56, height: 36),
        ],
      ),
    );
  }

  Widget _dataRow(List<SmartColumn<T>> cols, T row) {
    return InkWell(
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final col in cols)
              SizedBox(
                width: col.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  // قاعده ۴: shrink-to-fit — هیچ متنی از کادر بیرون نمی‌زند
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(col.display(row), style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ),
            if (widget.rowAction != null)
              SizedBox(width: 56, child: widget.rowAction!(row)),
          ],
        ),
      ),
    );
  }

  Widget _sumRow(List<SmartColumn<T>> cols, List<T> data) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cols.length; i++)
            SizedBox(
              width: cols[i].width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _cellSum(cols[i], data),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12.5,
                        color: Color(0xFF1E3A5F)),
                  ),
                ),
              ),
            ),
          if (widget.rowAction != null) const SizedBox(width: 56),
        ],
      ),
    );
  }

  String _cellSum(SmartColumn<T> col, List<T> data) {
    if (col.numeric == null) {
      return sortCol == widget.columns.indexOf(col) ? '${widget.sumLabel} ⬇' : widget.sumLabel;
    }
    var sum = 0.0;
    for (final r in data) {
      final v = col.numeric!.call(r);
      if (v != null) sum += v;
    }
    if (sum == sum.roundToDouble()) {
      return money(sum.round());
    }
    return toPersianDigits(sum.toStringAsFixed(1));
  }
}

extension on Color {
  /// سازگار با همه نسخه‌ها
  Color withOpacitySafe(double v) => withValues(alpha: v);
}
