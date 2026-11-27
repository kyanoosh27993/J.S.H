/// فاکتورها — فاز ۵ (بند ۱۳)
/// سربرگ‌های مجزا: پیش‌فاکتورها | فاکتورها | ابطال‌شده‌ها
/// هیچ فاکتوری حذف نمی‌شود؛ فقط ابطال می‌شود و به بخش ابطالی می‌رود.
/// حذف کامل فقط توسط مدیر اصلی برنامه (بند ۱۳) + QR و باز کردن با شماره (بند ۶).
library;

import 'package:flutter/material.dart';

import '../../core/db/db.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/data_table_pro.dart';
import '../../shared/widgets/qr_box.dart';
import '../orders/orders_page.dart' show printTicketReceipt, showFinancialsDialog;
import '../tickets/ticket_detail.dart';

class _InvoiceRow {
  final Map<String, Object?> inv;
  final Ticket ticket;
  final String customer;
  _InvoiceRow(this.inv, this.ticket, this.customer);
  int get id => (inv['id'] ?? 0) as int;
  String get number => (inv['number'] ?? '') as String;
  String get kind => (inv['kind'] ?? '') as String;
  String get status => (inv['status'] ?? 'active') as String;
  int get total => (inv['total'] ?? 0) as int;
  int get discount => (inv['discount'] ?? 0) as int;
  int get paid => (inv['paid'] ?? 0) as int;
  // فاز ۵b (بند ۱۲) — هزینه/خسارت و سود خالص
  int get cost => (inv['cost'] ?? 0) as int;
  int get damage => (inv['damage'] ?? 0) as int;
  int get netProfit => InvoiceRepo.netProfitOf(inv);
  int get remaining => total - discount - paid;
  bool get cancelled => status == 'cancelled';
}

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  bool loading = true;
  List<_InvoiceRow> all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // یک ردیف خراب نباید کل صفحه را خالی کند (بند ۲۰ نسخه ۳)
    try {
      await _loadData();
    } catch (e) {
      debugPrint('invoices _load error: $e');
    }
  }

  Future<void> _loadData() async {
    final db = await Db.instance();
    final invRows = await db.query('invoices', orderBy: 'id DESC');
    final cNames = await CustomerRepo.nameMap();
    final out = <_InvoiceRow>[];
    for (final inv in invRows) {
      final t = await TicketRepo.byId((inv['ticket_id'] ?? 0) as int);
      if (t == null) continue;
      out.add(_InvoiceRow(inv, t, cNames[t.customerId] ?? '-'));
    }
    if (!mounted) return;
    setState(() {
      all = out;
      loading = false;
    });
  }

  Future<void> _cancel(_InvoiceRow r) async {
    final me = AppSession.I.currentUser;
    if (!me!.can('action.invoice.edit')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی ابطال فاکتور برای شما مجاز نیست'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final reason = await _reasonDialog('ابطال سند ${toPersianDigits(r.number)}');
    if (reason == null || reason.trim().isEmpty) return;
    await InvoiceRepo.cancel(r.id, reason.trim(), userId: me.id);
    await InvoiceRepo.refreshForTicket(r.ticket.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('سند ابطال شد و به بخش ابطال‌شده‌ها منتقل شد'),
    ));
    _load();
  }

  Future<void> _restore(_InvoiceRow r) async {
    await InvoiceRepo.restore(r.id, userId: AppSession.I.currentUser?.id ?? 0);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سند از ابطال خارج شد')));
    _load();
  }

  /// حذف کامل — فقط مدیر اصلی (بند ۱۳) با هشدار دو مرحله‌ای
  Future<void> _deleteFully(_InvoiceRow r) async {
    final me = AppSession.I.currentUser;
    if (!me!.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('حذف کامل فقط توسط مدیر اصلی مجاز است'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('هشدار اول — حذف کامل'),
        content: Text(
            'سند ${toPersianDigits(r.number)} و همه اثرهای آن از سراسر برنامه حذف می‌شود.\n'
            'این عمل غیرقابل بازگشت است. ادامه؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ادامه')),
        ],
      ),
    );
    if (ok1 != true) return;
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('هشدار دوم — تایید نهایی'),
        content: const Text(
            'آیا مطمئنید؟ حذف کامل یعنی هیچ ردپایی از این سند باقی نمی‌ماند.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف کامل')),
        ],
      ),
    );
    if (ok2 != true) return;
    final err = await InvoiceRepo.deleteFully(r.id, actor: me);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'سند به‌طور کامل حذف شد'),
      backgroundColor: err != null ? Colors.red : null,
    ));
    _load();
  }

  /// اصلاح مبالغ فاکتور قطعی — بند ۱۲ (با لاگ قدیمی/جدید برای مدیر سیستم)
  Future<void> _editFinancials(_InvoiceRow r) async {
    final me = AppSession.I.currentUser;
    if (!me!.can('action.invoice.edit')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی اصلاح مبالغ برای شما مجاز نیست'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final fin = await showFinancialsDialog(
      context,
      cost: r.cost,
      discount: r.discount,
      damage: r.damage,
      damageUserId: r.inv['damage_user'] as int?,
      note: (r.inv['profit_note'] ?? '') as String,
    );
    if (fin == null) return;
    await InvoiceRepo.updateFinancials(
      r.id,
      cost: fin.cost,
      discount: fin.discount,
      damage: fin.damage,
      damageUserId: fin.damageUserId,
      profitNote: fin.note,
      userId: me.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('مبالغ اصلاح شد و در لاگ مدیر ثبت گردید'),
    ));
    _load();
  }

  /// چاپ/PDF — بند ۱۰.۷۱: اگر فاکتور pdf_path ثبت‌شده دارد همان معرفی می‌شود،
  /// وگرنه رسید سه‌برگی سفارش ساخته می‌شود.
  Future<void> _print(_InvoiceRow r) async {
    final pdfPath = ((r.inv['pdf_path'] ?? '') as String).trim();
    if (pdfPath.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('PDF ثبت‌شده سند: ${toPersianDigits(pdfPath)}')));
      return;
    }
    await printTicketReceipt(context, r.ticket);
  }

  /// نوار خلاصه هر سربرگ — بند ۱۲ (سود خالص) و بند ۲۳.۱۲۷ (خلاصه ابطالی‌ها)
  Widget _summaryBar(List<_InvoiceRow> list, {required bool cancelledTab}) {
    if (list.isEmpty) return const SizedBox.shrink();
    final chipStyle = TextStyle(
        fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (cancelledTab) {
      // بند ۲۳ — شمارش و جمع اسناد ابطالی به تفکیک پیش‌فاکتور/فاکتور
      final pre = list.where((r) => r.kind == InvoiceRepo.kindPre).toList();
      final fin =
          list.where((r) => r.kind == InvoiceRepo.kindFinal).toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(
              label: Text(
                'پیش‌فاکتور ابطالی: ${toPersianDigits('${pre.length}')} سند — ${money(pre.fold<int>(0, (s, r) => s + r.total))} تومان',
                style: chipStyle,
              ),
            ),
            Chip(
              label: Text(
                'فاکتور ابطالی: ${toPersianDigits('${fin.length}')} سند — ${money(fin.fold<int>(0, (s, r) => s + r.total))} تومان',
                style: chipStyle,
              ),
            ),
          ],
        ),
      );
    }
    final sumTotal = list.fold<int>(0, (s, r) => s + r.total);
    final sumDiscount = list.fold<int>(0, (s, r) => s + r.discount);
    final sumRemaining = list.fold<int>(0, (s, r) => s + r.remaining);
    final sumNet = list.fold<int>(0, (s, r) => s + r.netProfit);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          Chip(
              label: Text(
                  'تعداد: ${toPersianDigits('${list.length}')}', style: chipStyle)),
          Chip(
              label: Text('جمع: ${money(sumTotal)} تومان', style: chipStyle)),
          Chip(
              label: Text('تخفیف: ${money(sumDiscount)} تومان',
                  style: chipStyle)),
          Chip(
              label: Text('مانده: ${money(sumRemaining)} تومان',
                  style: chipStyle)),
          Chip(
              label: Text('سود خالص: ${money(sumNet)} تومان',
                  style: chipStyle),
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer),
        ],
      ),
    );
  }

  Future<String?> _reasonDialog(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'دلیل ابطال (الزامی)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('ابطال'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pre = all.where((r) => r.kind == InvoiceRepo.kindPre && !r.cancelled).toList();
    final fin = all.where((r) => r.kind == InvoiceRepo.kindFinal && !r.cancelled).toList();
    final cancelled = all.where((r) => r.cancelled).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('فاکتورها',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('به‌روزرسانی'),
                  ),
                ],
              ),
              AppText(
                'هیچ فاکتوری از برنامه حذف نمی‌شود — فقط ابطال می‌شود و به بخش ابطالی می‌رود (بند ۱۳). حذف کامل فقط توسط مدیر اصلی.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 6),
              const TabBar(
                tabs: [
                  Tab(text: 'پیش‌فاکتورها'),
                  Tab(text: 'فاکتورها'),
                  Tab(text: 'ابطال‌شده‌ها'),
                ],
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(children: [
                        _tab(pre, 'invoices_pre'),
                        _tab(fin, 'invoices_final'),
                        _tab(cancelled, 'invoices_cancelled', cancelled: true),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(List<_InvoiceRow> list, String tableId,
      {bool cancelled = false}) {
    return Column(
      children: [
        _summaryBar(list, cancelledTab: cancelled),
        Expanded(child: _table(list, tableId)),
      ],
    );
  }

  Widget _table(List<_InvoiceRow> list, String tableId) {
    if (list.isEmpty) {
      return const Center(child: Text('سندی در این بخش نیست'));
    }
    final isCancelledTab = tableId == 'invoices_cancelled';
    return SingleChildScrollView(
      child: DataTablePro<_InvoiceRow>(
        rows: list,
        tableId: tableId,
        searchIndex: (r) => '${r.number} ${r.ticket.code} ${r.customer}',
        onRowTap: (r) async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: r.ticket.id!),
          ));
          _load();
        },
        columns: [
          ProColumn<_InvoiceRow>(
            label: 'شماره سند',
            display: (r) => toPersianDigits(r.number),
            width: 180,
          ),
          ProColumn<_InvoiceRow>(
            label: 'کد سفارش',
            display: (r) => r.ticket.code,
            width: 150,
          ),
          ProColumn<_InvoiceRow>(
            label: 'مشتری',
            display: (r) => r.customer,
            width: 150,
            filterable: true,
          ),
          ProColumn<_InvoiceRow>(
            label: 'جمع',
            display: (r) => money(r.total),
            numeric: (r) => r.total,
            width: 120,
          ),
          ProColumn<_InvoiceRow>(
            label: 'تخفیف',
            display: (r) => money(r.discount),
            numeric: (r) => r.discount,
            width: 110,
          ),
          ProColumn<_InvoiceRow>(
            label: 'پرداخت‌شده',
            display: (r) => money(r.paid),
            numeric: (r) => r.paid,
            width: 120,
          ),
          ProColumn<_InvoiceRow>(
            label: 'مانده',
            display: (r) => money(r.remaining),
            numeric: (r) => r.remaining,
            width: 120,
          ),
          // فاز ۵b (بند ۱۲) — سود خالص: جمع منهای تخفیف، هزینه و خسارت
          ProColumn<_InvoiceRow>(
            label: 'سود خالص',
            display: (r) => money(r.netProfit),
            numeric: (r) => r.netProfit,
            width: 120,
          ),
          ProColumn<_InvoiceRow>(
            label: 'QR',
            display: (r) => '',
            width: 80,
          ),
          ProColumn<_InvoiceRow>(
            label: 'عملیات',
            display: (r) =>
                isCancelledTab ? ((r.inv['cancel_reason'] ?? '') as String) : '',
            width: 190,
          ),
        ],
        rowAction: (r) => Wrap(
          spacing: 4,
          children: [
            QrBox(data: '${r.ticket.code} ${r.number}', size: 60),
            // بند ۱۰.۷۱ — چاپ/PDF از لیست فاکتورها
            IconButton(
              tooltip: 'چاپ/PDF',
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              onPressed: () => _print(r),
            ),
            if (!isCancelledTab) ...[
              // بند ۱۲ — اصلاح مبالغ فاکتور قطعی (لاگ برای مدیر سیستم)
              if (r.kind == InvoiceRepo.kindFinal)
                IconButton(
                  tooltip: 'اصلاح مبالغ (هزینه/تخفیف/خسارت)',
                  icon: const Icon(Icons.edit_note, color: Colors.teal),
                  onPressed: () => _editFinancials(r),
                ),
              IconButton(
                tooltip: 'ابطال (انتقال به ابطال‌شده‌ها)',
                icon: const Icon(Icons.block, color: Colors.orange),
                onPressed: () => _cancel(r),
              )
            ] else ...[
              IconButton(
                tooltip: 'بازگردانی از ابطال',
                icon: const Icon(Icons.restore, color: Colors.green),
                onPressed: () => _restore(r),
              ),
              IconButton(
                tooltip: 'حذف کامل (فقط مدیر اصلی)',
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                onPressed: () => _deleteFully(r),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
