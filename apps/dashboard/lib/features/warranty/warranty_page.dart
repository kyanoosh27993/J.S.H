/// ماژول گارانتی — فاز ۲ + فاز ۶ (بند ۱۵)
/// گارانتی خودکار هنگام تحویل + پیگیری انقضا + تمدید + جدول پیشرفته
/// + سربرگ جدید: اقلام گارانتی‌دار با روزهای باقیمانده و انتقال خودکار منقضی‌ها
library;

import 'package:flutter/material.dart';

import '../../core/repos.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../core/warranty.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/data_table_pro.dart';
import '../tickets/ticket_detail.dart';

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

/// بند ۱۵ — گارانتی در سطح قلم: هر قلم با گارانتی خاص خود
/// از سفارش تحویل‌شده؛ با اتمام مدت، به دسته منقضی می‌رود
class _ItemWarrantyRow {
  final int ticketId;
  final String ticketCode;
  final String customerName;
  final String itemName;
  final DateTime start;
  final DateTime end;
  _ItemWarrantyRow({
    required this.ticketId,
    required this.ticketCode,
    required this.customerName,
    required this.itemName,
    required this.start,
    required this.end,
  });

  int get daysLeft => end.difference(DateTime.now()).inDays;
  bool get expired => daysLeft < 0;
  String get statusFa => expired ? 'منقضی' : (daysLeft <= 30 ? 'نزدیک انقضا' : 'فعال');
}

class WarrantyPage extends StatefulWidget {
  const WarrantyPage({super.key});

  @override
  State<WarrantyPage> createState() => _WarrantyPageState();
}

class _WarrantyPageState extends State<WarrantyPage> {
  List<_WarrantyRow> rows = [];
  List<_ItemWarrantyRow> itemRows = [];
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
    // بند ۱۵ — اقلام گارانتی‌دار سفارش‌های تحویل‌شده
    final cNames = await CustomerRepo.nameMap();
    final items = <_ItemWarrantyRow>[];
    for (final t in tickets) {
      if (t.status != 'delivered') continue;
      final its = await TicketItemRepo.byTicket(t.id!);
      final start = DateTime.tryParse(t.updatedAt) ?? DateTime.now();
      for (final it in its) {
        if (it.warrantyMonths <= 0) continue;
        items.add(_ItemWarrantyRow(
          ticketId: t.id!,
          ticketCode: t.code,
          customerName: cNames[t.customerId] ?? '-',
          itemName: it.description,
          start: start,
          end: DateTime(start.year, start.month + it.warrantyMonths, start.day),
        ));
      }
    }
    items.sort((x1, x2) => x1.daysLeft.compareTo(x2.daysLeft));
    final months = await WarrantyRepo.defaultMonths();
    if (!mounted) return;
    setState(() {
      rows = out;
      itemRows = items;
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
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'گارانتی سطح سفارش'),
                        Tab(text: 'اقلام گارانتی‌دار (بند ۱۵)'),
                      ],
                    ),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : TabBarView(children: [
                              _orderTab(p),
                              _itemTab(p),
                            ]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderTab(p) {
    if (rows.isEmpty) {
      return Center(
          child: AppText(
        'هنوز گارانتی‌ای ثبت نشده — با تحویل سفارش به‌صورت خودکار ساخته می‌شود',
        style: TextStyle(color: p.textSecondary, fontSize: 13),
      ));
    }
    return SingleChildScrollView(
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
            numeric: (r) => r.w.startDate.millisecondsSinceEpoch,
          ),
          ProColumn<_WarrantyRow>(
            label: 'پایان',
            display: (r) => shamsiDate(r.w.endDate),
            width: 120,
            numeric: (r) => r.w.endDate.millisecondsSinceEpoch,
          ),
          ProColumn<_WarrantyRow>(
            label: 'مدت (ماه)',
            display: (r) => toPersianDigits('${r.w.months}'),
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
          icon: Icon(Icons.update, size: 19, color: p.primary),
          onPressed: () => _extend(r),
        ),
      ),
    );
  }

  /// بند ۱۵ — اقلام گارانتی‌دار با روزهای باقیمانده؛ منقضی‌ها با فیلتر جدا
  Widget _itemTab(p) {
    if (itemRows.isEmpty) {
      return Center(
          child: AppText(
        'قلم گارانتی‌داری ثبت نشده — گارانتی قلم در جزئیات سفارش ثبت می‌شود',
        style: TextStyle(color: p.textSecondary, fontSize: 13),
      ));
    }
    return SingleChildScrollView(
      child: DataTablePro<_ItemWarrantyRow>(
        tableId: 'warranty_items',
        rows: itemRows,
        searchIndex: (r) =>
            '${r.ticketCode} ${r.customerName} ${r.itemName} ${r.statusFa}',
        columns: [
          ProColumn<_ItemWarrantyRow>(
            label: 'سفارش',
            display: (r) => r.ticketCode,
            width: 150,
          ),
          ProColumn<_ItemWarrantyRow>(
            label: 'مشتری',
            display: (r) => r.customerName,
            width: 150,
            filterable: true,
          ),
          ProColumn<_ItemWarrantyRow>(
            label: 'قلم',
            display: (r) => r.itemName,
            width: 180,
          ),
          ProColumn<_ItemWarrantyRow>(
            label: 'شروع',
            display: (r) => shamsiDate(r.start),
            width: 110,
            numeric: (r) => r.start.millisecondsSinceEpoch,
          ),
          ProColumn<_ItemWarrantyRow>(
            label: 'پایان',
            display: (r) => shamsiDate(r.end),
            width: 110,
            numeric: (r) => r.end.millisecondsSinceEpoch,
          ),
          ProColumn<_ItemWarrantyRow>(
            label: 'روزهای باقیمانده',
            display: (r) => r.expired
                ? 'منقضی — ${toPersianDigits('${-r.daysLeft}')} روز پیش'
                : toPersianDigits('${r.daysLeft}'),
            width: 150,
            numeric: (r) => r.daysLeft,
          ),
          ProColumn<_ItemWarrantyRow>(
            label: 'وضعیت',
            display: (r) => r.statusFa,
            width: 110,
            filterable: true,
          ),
        ],
        onRowTap: (r) async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: r.ticketId),
          ));
          _load();
        },
        rowAction: (r) => IconButton(
          tooltip: 'مشاهده سفارش / پیش‌فاکتور / فاکتور',
          icon: Icon(Icons.open_in_new, size: 19, color: p.primary),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TicketDetailPage(ticketId: r.ticketId),
            ));
            _load();
          },
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
