/// ماژول گارانتی — فاز ۲
/// گارانتی خودکار هنگام تحویل + پیگیری انقضا + تمدید + جدول پیشرفته
library;

import 'package:flutter/material.dart';

import '../../core/repos.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../core/warranty.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/data_table_pro.dart';

class _WarrantyRow {
  final WarrantyRecord w;
  final String ticketCode;
  final String customerName;
  _WarrantyRow(this.w, this.ticketCode, this.customerName);

  String get statusFa => switch (w.liveStatus()) {
        'expired' => 'منقضی',
        'expiring' => 'نزدیک انقضا',
        _ => 'فعال',
      };
}

class WarrantyPage extends StatefulWidget {
  const WarrantyPage({super.key});

  @override
  State<WarrantyPage> createState() => _WarrantyPageState();
}

class _WarrantyPageState extends State<WarrantyPage> {
  List<_WarrantyRow> rows = [];
  bool loading = true;
  int nActive = 0, nExpiring = 0, nExpired = 0;
  int defaultMonths = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final warranties = await WarrantyRepo.all();
    final tickets = await TicketRepo.all();
    final ticketById = {for (final t in tickets) t.id!: t};
    final out = <_WarrantyRow>[];
    var a = 0, e = 0, x = 0;
    for (final w in warranties) {
      final t = ticketById[w.ticketId];
      final c = t == null ? null : await CustomerRepo.byId(t.customerId);
      out.add(_WarrantyRow(w, t?.code ?? '—', c?.name ?? '—'));
      switch (w.liveStatus()) {
        case 'active':
          a++;
          break;
        case 'expiring':
          e++;
          break;
        default:
          x++;
      }
    }
    final months = await WarrantyRepo.defaultMonths();
    if (!mounted) return;
    setState(() {
      rows = out;
      nActive = a;
      nExpiring = e;
      nExpired = x;
      defaultMonths = months;
      loading = false;
    });
  }

  Future<void> _extend(_WarrantyRow r) async {
    final ctrl = TextEditingController(text: '$defaultMonths');
    final months = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تمدید گارانتی ${r.ticketCode}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'چند ماه تمدید شود؟'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx,
                  int.tryParse(toEnglishDigits(ctrl.text))),
              child: const Text('تمدید')),
        ],
      ),
    );
    if (months == null || months <= 0) return;
    await WarrantyRepo.extend(r.w.ticketId, months);
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('گارانتی ${r.ticketCode} $months ماه تمدید شد')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppText('گارانتی‌ها',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 10),
                _chip('فعال', nActive, p.success),
                _chip('نزدیک انقضا', nExpiring, p.warning),
                _chip('منقضی', nExpired, p.danger),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() => loading = true);
                    _load();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('به‌روزرسانی'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: p.surfaceAlt,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: AppText(
                  'هنگام تحویل سفارش، گارانتی به‌صورت خودکار با $defaultMonths ماه (قابل تغییر در تنظیمات) ساخته می‌شود. '
                  'گارانتی‌های ۳۰ روز به انقضا با رنگ هشدار نشان داده می‌شوند و با یک کلیک تمدید می‌شوند.',
                  style: TextStyle(
                      fontSize: 12, height: 1.7, color: p.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? Center(
                          child: AppText(
                          'هنوز گارانتی‌ای ثبت نشده — با تحویل سفارش به‌صورت خودکار ساخته می‌شود',
                          style: TextStyle(color: p.textSecondary, fontSize: 13),
                        ))
                      : SingleChildScrollView(
                          child: DataTablePro<_WarrantyRow>(
                            tableId: 'warranties',
                            rows: rows,
                            searchIndex: (r) =>
                                '${r.ticketCode} ${r.customerName} ${r.statusFa}',
                            columns: [
                              ProColumn<_WarrantyRow>(
                                label: 'سفارش',
                                display: (r) => r.ticketCode,
                                width: 150,
                              ),
                              ProColumn<_WarrantyRow>(
                                label: 'مشتری',
                                display: (r) => r.customerName,
                                width: 170,
                                filterable: true,
                              ),
                              ProColumn<_WarrantyRow>(
                                label: 'شروع',
                                display: (r) => shamsiDate(r.w.startDate),
                                width: 120,
                                numeric: (r) =>
                                    r.w.startDate.millisecondsSinceEpoch,
                              ),
                              ProColumn<_WarrantyRow>(
                                label: 'پایان',
                                display: (r) => shamsiDate(r.w.endDate),
                                width: 120,
                                numeric: (r) =>
                                    r.w.endDate.millisecondsSinceEpoch,
                              ),
                              ProColumn<_WarrantyRow>(
                                label: 'مدت (ماه)',
                                display: (r) =>
                                    toPersianDigits('${r.w.months}'),
                                width: 100,
                                numeric: (r) => r.w.months,
                              ),
                              ProColumn<_WarrantyRow>(
                                label: 'وضعیت',
                                display: (r) => r.statusFa,
                                width: 120,
                                filterable: true,
                              ),
                            ],
                            rowAction: (r) => IconButton(
                              tooltip: 'تمدید',
                              icon: Icon(Icons.update,
                                  size: 19, color: p.primary),
                              onPressed: () => _extend(r),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int n, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Chip(
        backgroundColor: color.withValues(alpha: 0.14),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        avatar: Icon(
            n > 0 ? Icons.circle : Icons.radio_button_unchecked,
            size: 12,
            color: color),
        label: AppNumText(
            '$label: ${toPersianDigits('$n')}',
            style: TextStyle(fontSize: 11.5, color: color)),
      ),
    );
  }
}
