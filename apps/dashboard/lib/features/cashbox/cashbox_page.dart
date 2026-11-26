/// صندوق — فاز ۵ (بند ۱۴)
/// سربرگ ۱: سفارشات تسویه‌نشده (پیش‌فاکتورها) — تسویه مانده، تخفیف نقدی/درصدی،
/// افزودن قلم؛ سربرگ ۲: فاکتورهای تسویه‌شده.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';
import '../../shared/widgets/data_table_pro.dart';
import '../../shared/widgets/persian_number_field.dart';
import '../tickets/ticket_detail.dart';

class _CashRow {
  final Ticket ticket;
  final String customer;
  final Map<String, Object?>? invoice;
  _CashRow(this.ticket, this.customer, this.invoice);
  int get total => ((invoice?['total'] ?? 0) as int) == 0
      ? ticket.estimateAmount
      : (invoice?['total'] ?? 0) as int;
  int get paid => (invoice?['paid'] ?? 0) as int;
  int get discount => (invoice?['discount'] ?? 0) as int;
  int get remaining => total - discount - paid;
  bool get settled => remaining <= 0;
  String get number => (invoice?['number'] ?? '') as String;
  int get invoiceId => (invoice?['id'] ?? 0) as int;
}

class CashboxPage extends StatefulWidget {
  const CashboxPage({super.key});

  @override
  State<CashboxPage> createState() => _CashboxPageState();
}

class _CashboxPageState extends State<CashboxPage> {
  bool loading = true;
  List<_CashRow> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final cNames = await CustomerRepo.nameMap();
    final invoices = await InvoiceRepo.allByTicketMap();
    final out = <_CashRow>[];
    for (final t in tickets) {
      final inv = invoices[t.id];
      // فاکتور ابطالی در صندوق نمایش داده نمی‌شود
      if (inv != null && (inv['status'] ?? '') == 'cancelled') continue;
      out.add(_CashRow(
        t,
        cNames[t.customerId] ?? '-',
        inv,
      ));
    }
    if (!mounted) return;
    setState(() {
      rows = out;
      loading = false;
    });
  }

  Future<void> _settle(_CashRow r) async {
    final me = AppSession.I.currentUser;
    if (!me!.can('action.ticket.settle')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی تسویه برای شما مجاز نیست'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (r.invoiceId == 0) {
      // هنوز سندی ندارد — پیش‌فاکتور بساز
      await InvoiceRepo.createFromTicket(
          ticket: r.ticket, kind: InvoiceRepo.kindPre);
      await _load();
    }
    final ctrl = TextEditingController(text: '${r.remaining}');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تسویه ${toPersianDigits(r.ticket.code)}'),
          content: PersianNumberField(
            label: 'مبلغ وصول (تومان)',
            controller: ctrl,
            hint: '${r.remaining}',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx,
                  int.tryParse(
                          toEnglishDigits(ctrl.text).replaceAll(',', '')) ??
                      0),
              child: const Text('ثبت وصول'),
            ),
          ],
        ),
      ),
    );
    if (amount == null || amount <= 0) return;
    await InvoiceRepo.settle(r.invoiceId, r.ticket.id!,
        amount: amount, userId: me.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('وصول ثبت شد')));
    _load();
  }

  Future<void> _discount(_CashRow r) async {
    if (r.invoiceId == 0) return;
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تخفیف'),
          content: const Text('نوع تخفیف را انتخاب کنید (بند ۱۴)'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'amount'),
                child: const Text('نقدی (تومان)')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'percent'),
                child: const Text('درصدی')),
          ],
        ),
      ),
    );
    if (kind == null) return;
    final ctrl = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(kind == 'amount' ? 'تخفیف نقدی' : 'تخفیف درصدی'),
          content: PersianNumberField(
            label: kind == 'amount' ? 'مبلغ (تومان)' : 'درصد',
            controller: ctrl,
            hint: '0',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx,
                  double.tryParse(
                      toEnglishDigits(ctrl.text).replaceAll(',', '')) ??
                  0),
              child: const Text('اعمال'),
            ),
          ],
        ),
      ),
    );
    if (value == null || value <= 0) return;
    if (kind == 'amount') {
      await InvoiceRepo.applyDiscount(r.invoiceId, amount: value.round());
    } else {
      await InvoiceRepo.applyDiscount(r.invoiceId, percent: value);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تخفیف اعمال شد')));
    _load();
  }

  /// افزودن قلم به سفارش از صندوق (بند ۱۴)
  Future<void> _addItem(_CashRow r) async {
    final desc = TextEditingController();
    final price = TextEditingController();
    final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('افزودن قلم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: desc,
                decoration:
                    const InputDecoration(labelText: 'شرح قلم *'),
              ),
              const SizedBox(height: 8),
              PersianNumberField(label: 'تعداد', controller: qty, hint: '1'),
              const SizedBox(height: 8),
              PersianNumberField(
                  label: 'قیمت واحد (تومان) *', controller: price, hint: '0'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('افزودن')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final p = int.tryParse(toEnglishDigits(price.text)) ?? 0;
    final q = int.tryParse(toEnglishDigits(qty.text)) ?? 1;
    if (desc.text.trim().isEmpty || p <= 0) return;
    await TicketItemRepo.insert(TicketItem(
      ticketId: r.ticket.id!,
      description: desc.text.trim(),
      qty: q,
      price: p,
    ));
    await InvoiceRepo.refreshForTicket(r.ticket.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('قلم افزوده و فاکتور به‌روز شد')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final unsettled = rows.where((r) => !r.settled).toList();
    final settled = rows.where((r) => r.settled).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('صندوق',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('به‌روزرسانی'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const TabBar(
                tabs: [
                  Tab(text: 'تسویه‌نشده (پیش‌فاکتورها)'),
                  Tab(text: 'فاکتورهای تسویه‌شده'),
                ],
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(children: [
                        _table(unsettled, 'cashbox_unsettled'),
                        _table(settled, 'cashbox_settled'),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _table(List<_CashRow> list, String tableId) {
    if (list.isEmpty) {
      return const Center(child: Text('ردیفی نیست'));
    }
    return SingleChildScrollView(
      child: DataTablePro<_CashRow>(
        rows: list,
        tableId: tableId,
        searchIndex: (r) => '${r.ticket.code} ${r.customer} ${r.number}',
        onRowTap: (r) async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: r.ticket.id!),
          ));
          _load();
        },
        columns: [
          ProColumn<_CashRow>(
            label: 'کد سفارش',
            display: (r) => r.ticket.code,
            width: 150,
          ),
          ProColumn<_CashRow>(
            label: 'مشتری',
            display: (r) => r.customer,
            width: 150,
            filterable: true,
          ),
          ProColumn<_CashRow>(
            label: 'شماره سند',
            display: (r) => r.number.isEmpty ? '—' : toPersianDigits(r.number),
            width: 170,
          ),
          ProColumn<_CashRow>(
            label: 'جمع',
            display: (r) => money(r.total),
            numeric: (r) => r.total,
            width: 130,
          ),
          ProColumn<_CashRow>(
            label: 'تخفیف',
            display: (r) => money(r.discount),
            numeric: (r) => r.discount,
            width: 110,
          ),
          ProColumn<_CashRow>(
            label: 'پرداخت‌شده',
            display: (r) => money(r.paid),
            numeric: (r) => r.paid,
            width: 130,
          ),
          ProColumn<_CashRow>(
            label: 'مانده',
            display: (r) => money(r.remaining),
            numeric: (r) => r.remaining,
            width: 130,
          ),
          ProColumn<_CashRow>(
            label: 'وضعیت',
            display: (r) => r.settled ? 'تسویه‌شده' : 'بدهکار',
            width: 100,
            filterable: true,
          ),
          ProColumn<_CashRow>(
            label: 'عملیات',
            display: (r) => '',
            width: 150,
          ),
        ],
        rowAction: (r) => Wrap(
          spacing: 4,
          children: [
            if (!r.settled) ...[
              IconButton(
                tooltip: 'تسویه مانده',
                icon: const Icon(Icons.payments, size: 18),
                onPressed: () => _settle(r),
              ),
              IconButton(
                tooltip: 'تخفیف نقدی/درصدی',
                icon: const Icon(Icons.percent, size: 18),
                onPressed: () => _discount(r),
              ),
              IconButton(
                tooltip: 'افزودن قلم',
                icon: const Icon(Icons.playlist_add, size: 18),
                onPressed: () => _addItem(r),
              ),
            ] else
              const Icon(Icons.check_circle, size: 18, color: Colors.green),
          ],
        ),
      ),
    );
  }
}
