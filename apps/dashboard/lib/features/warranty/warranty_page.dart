/// ماژول گارانتی — فاز ۲ + فاز ۶ (بند ۱۵) + فاز ۹ (بند ۲۵)
/// دفتر گارانتی قلم‌به‌قلم: هر قلم گارانتی‌دار سفارش‌های تحویل‌شده و
/// رکوردهای warranty_records در یک فهرست گروه‌بندی‌شده بر پایه سفارش؛
/// روز باقیمانده رنگ‌بندی‌شده، دو تب «فعال» و «منقضی/غیرفعال» (بند ۲۵:
/// منقضی‌ها در تب غیرفعال)، برگه اقدام هر ردیف: مشاهده سفارش / مشاهده فاکتور /
/// کاهش یا ابطال گارانتی / افزایش مدت — ثبت در warranty_adjusts + حسابرسی.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../core/warranty.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/shamsi_date_field.dart';
import '../tickets/ticket_detail.dart';

/// یک ردیف دفتر گارانتی — یا گارانتی سطح سفارش (warranty_records) یا
/// گارانتی یک قلم خاص (ticket_items با warranty_months>0)
class _LedgerRow {
  final int ticketId;
  final String ticketCode;
  final String customerName;
  final String itemName; // سطح سفارش: «گارانتی کل سفارش»
  final bool isOrderLevel;
  final int? itemId;
  final DateTime start;
  final DateTime baseEnd; // تاریخ پایان محاسبه‌شده (پیش از تنظیم‌ها)
  final WarrantyAdjust? adjust; // آخرین تنظیم حاکم — فاز ۹ بند ۲۵
  final int months;

  _LedgerRow({
    required this.ticketId,
    required this.ticketCode,
    required this.customerName,
    required this.itemName,
    required this.isOrderLevel,
    required this.itemId,
    required this.start,
    required this.baseEnd,
    required this.months,
    this.adjust,
  });

  /// تاریخ پایان نمایشی — آخرین تنظیم بر محاسبه اولیه مقدم است
  DateTime get end => adjust?.newEnd ?? baseEnd;

  /// گارانتی ابطال‌شده = غیرفعال
  bool get voided => adjust?.action == 'void';

  int get daysLeft => end.difference(DateTime.now()).inDays;

  /// بند ۲۵ — غیرفعال: ابطال‌شده یا تاریخ گذشته (به تب «منقضی/غیرفعال» می‌رود)
  bool get inactive => voided || daysLeft < 0;

  String get daysFa {
    if (voided) return 'ابطال‌شده';
    if (daysLeft < 0) return 'منقضی — ${toPersianDigits('${-daysLeft}')} روز پیش';
    return toPersianDigits('$daysLeft');
  }

  String get statusFa {
    if (voided) return 'ابطال‌شده';
    if (daysLeft < 0) return 'منقضی';
    if (daysLeft <= 30) return 'نزدیک انقضا';
    return 'فعال';
  }
}

class WarrantyPage extends StatefulWidget {
  const WarrantyPage({super.key});

  @override
  State<WarrantyPage> createState() => _WarrantyPageState();
}

class _WarrantyPageState extends State<WarrantyPage> {
  List<_LedgerRow> allRows = [];
  bool loading = true;
  bool showInactive = false; // بند ۲۵ — تب فعال / منقضی و غیرفعال
  String query = '';
  int defaultMonths = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final cNames = await CustomerRepo.nameMap();
    final out = <_LedgerRow>[];

    // بند ۲۵ — فرمول شروع قلم، همان فرمول WarrantyRepo.upsertForTicket است:
    // شروع = لحظه تحویل (آخرین به‌روزرسانی وضعیت سفارش = updatedAt هنگام
    // ثبت وضعیت delivered) و پایان = ماه شروع + ماه‌های گارانتی قلم.
    // نکته تست فاز ۴: منبع شمارش اقلام گارانتی‌دار (ticket_items) باید
    // تأیید شود — گارانتی قلم فقط از اقلام تحویل‌شده ساخته می‌شود.
    for (final t in tickets) {
      if (t.status != 'delivered') continue;
      final its = await TicketItemRepo.byTicket(t.id!);
      final start = DateTime.tryParse(t.updatedAt) ?? DateTime.now();
      final adjusts = await WarrantyAdjustRepo.forTicket(t.id!);
      WarrantyAdjust? adjustOf(int? itemId) {
        // آخرین تنظیم هر (ticket, item) — ردیف‌ها به ترتیب id ثبت شده‌اند
        WarrantyAdjust? latest;
        for (final a in adjusts) {
          if (a.itemId == itemId) latest = a;
        }
        return latest;
      }

      // گارانتی سطح سفارش — رکورد warranty_records در لحظه تحویل ساخته می‌شود
      final rec = await WarrantyRepo.forTicket(t.id!);
      if (rec != null) {
        out.add(_LedgerRow(
          ticketId: t.id!,
          ticketCode: t.code,
          customerName: cNames[t.customerId] ?? '—',
          itemName: 'گارانتی کل سفارش',
          isOrderLevel: true,
          itemId: null,
          start: rec.startDate,
          baseEnd: rec.endDate,
          months: rec.months,
          adjust: adjustOf(null),
        ));
      }
      // گارانتی قلم‌به‌قلم — هر قلم با warranty_months>0
      for (final it in its) {
        if (it.warrantyMonths <= 0) continue;
        out.add(_LedgerRow(
          ticketId: t.id!,
          ticketCode: t.code,
          customerName: cNames[t.customerId] ?? '—',
          itemName: it.description,
          isOrderLevel: false,
          itemId: it.id,
          start: start,
          baseEnd: DateTime(start.year, start.month + it.warrantyMonths, start.day),
          months: it.warrantyMonths,
          adjust: adjustOf(it.id),
        ));
      }
    }

    // گروه‌بندی بر پایه سفارش: مرتب بر کد سفارش، روزهای باقیمانده صعودی
    out.sort((a, b) {
      final c = a.ticketCode.compareTo(b.ticketCode);
      if (c != 0) return c;
      return a.daysLeft.compareTo(b.daysLeft);
    });
    final months = await WarrantyRepo.defaultMonths();
    if (!mounted) return;
    setState(() {
      allRows = out;
      defaultMonths = months;
      loading = false;
    });
  }

  List<_LedgerRow> get _filtered {
    final q = toEnglishDigits(query.trim().toLowerCase());
    return allRows.where((r) {
      if (r.inactive != showInactive) return false;
      if (q.isEmpty) return true;
      return '${r.ticketCode} ${r.customerName} ${r.itemName} ${r.statusFa}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  /// گروه‌بندی ردیف‌ها بر پایه سفارش — سربرگ هر گروه: کد سفارش و مشتری
  Map<String, List<_LedgerRow>> get _grouped {
    final map = <String, List<_LedgerRow>>{};
    for (final r in _filtered) {
      map.putIfAbsent('${r.ticketCode} — ${r.customerName}', () => []).add(r);
    }
    return map;
  }

  int get _nActive =>
      allRows.where((r) => !r.inactive && !r.voided && r.daysLeft > 30).length;
  int get _nExpiring => allRows
      .where((r) => !r.inactive && !r.voided && r.daysLeft <= 30)
      .length;
  int get _nInactive => allRows.where((r) => r.inactive).length;

  int get _userId => AppSession.I.currentUser?.id ?? 0;

  // ── برگه اقدام ردیف (بند ۲۵) ──────────────────────────────────────────

  Future<void> _rowActions(_LedgerRow r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('مشاهده سفارش'),
                onTap: () => Navigator.pop(ctx, 'ticket'),
              ),
              ListTile(
                leading: const Icon(Icons.request_quote),
                title: const Text('مشاهده فاکتور'),
                onTap: () => Navigator.pop(ctx, 'invoice'),
              ),
              ListTile(
                leading: Icon(Icons.content_cut,
                    color: Theme.of(ctx).colorScheme.error),
                title: const Text('کاهش/ابطال گارانتی'),
                onTap: () => Navigator.pop(ctx, 'reduce'),
              ),
              ListTile(
                leading: const Icon(Icons.update),
                title: const Text('افزایش مدت'),
                onTap: () => Navigator.pop(ctx, 'extend'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'ticket':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TicketDetailPage(ticketId: r.ticketId),
        ));
        _load();
        break;
      case 'invoice':
        await _showInvoice(r);
        break;
      case 'reduce':
        await _reduceOrVoid(r);
        break;
      case 'extend':
        await _extendMonths(r);
        break;
    }
  }

  /// مشاهده فاکتور — فاکتورها سربرگ سراسری هستند؛ اطلاعات سند سفارش در
  /// دیالوگ از InvoiceRepo.mainForTicket نشان داده می‌شود.
  Future<void> _showInvoice(_LedgerRow r) async {
    final inv = await InvoiceRepo.mainForTicket(r.ticketId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('سند سفارش ${toPersianDigits(r.ticketCode)}'),
          content: inv == null
              ? const Text('برای این سفارش سندی صادر نشده است.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('شماره: ${toPersianDigits((inv['number'] ?? '') as String)}'),
                    Text(
                        'نوع: ${(inv['kind'] ?? '') == InvoiceRepo.kindPre ? 'پیش‌فاکتور' : 'فاکتور قطعی'}'),
                    Text('جمع: ${moneyToman((inv['total'] ?? 0) as int)}'),
                    Text('مانده: ${moneyToman((inv['remaining'] ?? 0) as int)}'),
                    if ((inv['status'] ?? '') == 'cancelled')
                      Text('وضعیت: ابطال‌شده — دلیل: ${(inv['cancel_reason'] ?? '') as String}',
                          style: const TextStyle(color: Colors.red)),
                  ],
                ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('خب')),
          ],
        ),
      ),
    );
  }

  /// کاهش مدت یا ابطال کامل — تاریخ پایان جدید + دلیل، ثبت در
  /// warranty_adjusts با action reduce/void + لاگ حسابرسی warranty_adjust
  Future<void> _reduceOrVoid(_LedgerRow r) async {
    final reasonCtrl = TextEditingController();
    DateTime? newEnd;
    var voidIt = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('کاهش/ابطال گارانتی ${toPersianDigits(r.ticketCode)}'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('کاهش مدت'), icon: Icon(Icons.content_cut, size: 16)),
                      ButtonSegment(value: true, label: Text('ابطال کامل'), icon: Icon(Icons.block, size: 16)),
                    ],
                    selected: {voidIt},
                    onSelectionChanged: (s) => setD(() => voidIt = s.first),
                  ),
                  const SizedBox(height: 10),
                  Text(
                      'پایان فعلی: ${shamsiDate(r.end)}',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 10),
                  if (!voidIt) ...[
                    SizedBox(
                      width: 220,
                      child: ShamsiDateField(
                        label: 'تاریخ پایان جدید (شمسی)',
                        initial: r.end,
                        onChanged: (d) => newEnd = d,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'دلیل (ثبت در گزارش فعالیت‌ها)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('انصراف')),
              FilledButton(
                onPressed: () {
                  if (!voidIt && newEnd == null) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('ثبت'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    await WarrantyAdjustRepo.add(
      ticketId: r.ticketId,
      itemId: r.itemId,
      oldEnd: r.end,
      newEnd: voidIt ? DateTime.now() : newEnd!,
      action: voidIt ? 'void' : 'reduce',
      reason: reason,
      userId: _userId,
    );
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(voidIt
            ? 'گارانتی ${toPersianDigits(r.ticketCode)} ابطال شد'
            : 'تاریخ پایان گارانتی ${toPersianDigits(r.ticketCode)} به ${shamsiDate(newEnd!)} تغییر کرد'),
      ));
    }
  }

  /// افزایش مدت — افزودن ماه به پایان فعلی، ثبت در warranty_adjusts (extend)
  Future<void> _extendMonths(_LedgerRow r) async {
    final ctrl = TextEditingController(text: '$defaultMonths');
    final months = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('افزایش مدت گارانتی ${toPersianDigits(r.ticketCode)}'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'چند ماه افزوده شود؟'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    ctx, int.tryParse(toEnglishDigits(ctrl.text))),
                child: const Text('افزودن')),
          ],
        ),
      ),
    );
    if (months == null || months <= 0 || !mounted) return;
    final base = r.end;
    await WarrantyAdjustRepo.add(
      ticketId: r.ticketId,
      itemId: r.itemId,
      oldEnd: base,
      newEnd: DateTime(base.year, base.month + months, base.day),
      action: 'extend',
      reason: 'افزایش $months ماه',
      userId: _userId,
    );
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'گارانتی ${toPersianDigits(r.ticketCode)} $months ماه افزایش یافت')));
    }
  }

  // ── رابط کاربری ────────────────────────────────────────────────────────

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
                AppText('دفتر گارانتی — قلم‌به‌قلم (بند ۲۵)',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 10),
                _chip('فعال', _nActive, p.success),
                _chip('نزدیک انقضا', _nExpiring, p.warning),
                _chip('منقضی/غیرفعال', _nInactive, p.danger),
                const Spacer(),
                SizedBox(
                  width: 200,
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'جستجوی سفارش/مشتری/قلم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'به‌روزرسانی',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    setState(() => loading = true);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('فعال')),
                ButtonSegment(value: true, label: Text('منقضی/غیرفعال')),
              ],
              selected: {showInactive},
              onSelectionChanged: (s) => setState(() => showInactive = s.first),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppText(
                'هنگام تحویل، گارانتی کل سفارش و هر قلم گارانتی‌دار جدا ثبت می‌شود؛ '
                'کلیک روی هر ردیف: مشاهده سفارش، مشاهده فاکتور، کاهش/ابطال یا افزایش مدت '
                '(تاریخ پایان آخرین تنظیم حاکم است).',
                style: TextStyle(
                    fontSize: 12, height: 1.7, color: p.textSecondary),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildLedger(p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedger(p) {
    final groups = _grouped;
    if (groups.isEmpty) {
      return Center(
        child: AppText(
          showInactive
              ? 'مورد منقضی یا ابطال‌شده‌ای نیست — همه گارانتی‌ها فعال‌اند'
              : 'قلم گارانتی‌داری فعال نیست — گارانتی در جزئیات سفارش و هنگام تحویل ثبت می‌شود',
          style: TextStyle(color: p.textSecondary, fontSize: 13),
        ),
      );
    }
    return ListView(
      children: [
        for (final e in groups.entries) ...[
          // سربرگ گروه سفارش
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: p.border, width: 0.7),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt_long,
                    size: 15, color: p.textSecondary),
                const SizedBox(width: 6),
                AppText(e.key,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.bold)),
                const Spacer(),
                AppNumText(
                    '${toPersianDigits('${e.value.length}')} قلم',
                    style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
              ],
            ),
          ),
          for (final r in e.value) _ledgerCard(r, p),
        ],
      ],
    );
  }

  Widget _ledgerCard(_LedgerRow r, p) {
    // رنگ روز باقیمانده — سبز فعال، کهربایی نزدیک انقضا، قرمز منقضی، خاکستری ابطال
    final color = r.voided
        ? Colors.grey
        : r.daysLeft < 0
            ? p.danger
            : r.daysLeft <= 30
                ? p.warning
                : p.success;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _rowActions(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                r.isOrderLevel ? Icons.inventory_2 : Icons.widgets,
                size: 17,
                color: p.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(r.itemName,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    if (r.adjust != null)
                      Text(
                        '${r.adjust!.actionFa}: ${shamsiDate(r.adjust!.oldEnd)} ← ${shamsiDate(r.adjust!.newEnd)}'
                        '${r.adjust!.reason.isEmpty ? '' : ' — ${r.adjust!.reason}'}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: r.voided
                                ? Colors.grey
                                : p.textSecondary,
                            fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text('شروع: ${shamsiDate(r.start)}',
                    style: const TextStyle(fontSize: 11.5)),
              ),
              Expanded(
                flex: 2,
                child: Text('پایان: ${shamsiDate(r.end)}',
                    style: const TextStyle(fontSize: 11.5)),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: color.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '${r.daysFa} — ${r.statusFa}',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold,
                        color: color),
                  ),
                ),
              ),
              const Icon(Icons.more_vert, size: 16, color: Colors.grey),
            ],
          ),
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
        label: AppNumText('$label: ${toPersianDigits('$n')}',
            style: TextStyle(fontSize: 11.5, color: color)),
      ),
    );
  }
}
