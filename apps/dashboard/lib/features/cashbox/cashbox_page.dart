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
import '../orders/orders_page.dart' show printTicketReceipt;

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
    // بند ۲۳ — فاکتور ابطالی هرگز در صندوق دیده نمی‌شود
    final invoices = await InvoiceRepo.activeByTicketMap();
    final out = <_CashRow>[];
    for (final t in tickets) {
      final inv = invoices[t.id];
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

  /// فرم تسویه حساب — بازطراحی صندوق (بند ۲۴)
  /// کلیک روی ردیف، برگه تسویه با سربرگ سند، فیلد مبلغ با جداسازی سه‌رقمی،
  /// دکمه‌های سریع و چاپ را باز می‌کند. دسترسی: action.ticket.settle
  Future<void> _openSettleSheet(_CashRow r0) async {
    final me = AppSession.I.currentUser;
    if (!me!.can('action.ticket.settle')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی تسویه برای شما مجاز نیست'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    var row = r0;
    if (row.invoiceId == 0) {
      // هنوز سندی ندارد — پیش‌فاکتور بساز
      await InvoiceRepo.createFromTicket(
          ticket: row.ticket, kind: InvoiceRepo.kindPre);
      final invoices = await InvoiceRepo.allByTicketMap();
      final inv = invoices[row.ticket.id];
      if (inv != null) row = _CashRow(row.ticket, row.customer, inv);
    }
    if (!mounted) return;
    final amountCtrl = TextEditingController(text: '${row.remaining}');
    Future<void> refreshRow(void Function() sbSet) async {
      final invoices = await InvoiceRepo.allByTicketMap();
      final inv = invoices[row.ticket.id];
      sbSet(() {
        if (inv != null) row = _CashRow(row.ticket, row.customer, inv);
        amountCtrl.text = '${row.remaining > 0 ? row.remaining : 0}';
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, sbSet) => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('فرم تسویه حساب (بند ۲۴)',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  // سربرگ سند — شماره/جمع/پرداخت‌شده/مانده
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text('سند: ${row.number.isEmpty ? '—' : toPersianDigits(row.number)}',
                            style: const TextStyle(fontSize: 12.5)),
                        Text('جمع: ${money(row.total)}',
                            style: const TextStyle(fontSize: 12.5)),
                        Text('پرداخت‌شده: ${money(row.paid)}',
                            style: const TextStyle(fontSize: 12.5)),
                        Text('مانده: ${money(row.remaining)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: row.remaining > 0
                                  ? Colors.red
                                  : Colors.green,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // مبلغ وصول با جداسازی سه‌رقمی حین تایپ (بند ۲۴)
                  PersianNumberField(
                    label: 'مبلغ وصول (تومان)',
                    controller: amountCtrl,
                    hint: '${row.remaining > 0 ? row.remaining : 0}',
                    groupThousands: true,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('تسویه کامل'),
                        onPressed: () => sbSet(() =>
                            amountCtrl.text = '${row.remaining > 0 ? row.remaining : 0}'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.percent, size: 18),
                        label: const Text('تخفیف نقدی'),
                        onPressed: () async {
                          await _discountAmount(row);
                          refreshRow(sbSet);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.percent, size: 18),
                        label: const Text('تخفیف درصدی'),
                        onPressed: () async {
                          await _discountPercent(row);
                          refreshRow(sbSet);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('افزودن قلم'),
                        onPressed: () async {
                          await _addItem(row);
                          refreshRow(sbSet);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_remove, size: 18),
                        label: const Text('کسر قلم'),
                        onPressed: () async {
                          await _removeItem(row);
                          refreshRow(sbSet);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('چاپ'),
                      onPressed: () => printTicketReceipt(ctx, row.ticket),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.payments, size: 18),
                        label: const Text('ثبت وصول'),
                        onPressed: () async {
                          final amount = int.tryParse(toEnglishDigits(
                                  amountCtrl.text)
                              .replaceAll(',', '')) ??
                              0;
                          if (amount <= 0) return;
                          await InvoiceRepo.settle(row.invoiceId,
                              row.ticket.id!,
                              amount: amount, userId: me.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    amountCtrl.dispose();
    _load();
  }

  /// تخفیف نقدی (بند ۲۴)
  Future<void> _discountAmount(_CashRow r) async {
    final ctrl = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تخفیف نقدی'),
          content: PersianNumberField(
              label: 'مبلغ (تومان)', controller: ctrl, hint: '0'),
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
              child: const Text('اعمال'),
            ),
          ],
        ),
      ),
    );
    if (value == null || value <= 0 || r.invoiceId == 0) return;
    await InvoiceRepo.applyDiscount(r.invoiceId, amount: value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تخفیف اعمال شد')));
    _load();
  }

  /// تخفیف درصدی (بند ۲۴)
  Future<void> _discountPercent(_CashRow r) async {
    final ctrl = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تخفیف درصدی'),
          content: PersianNumberField(
              label: 'درصد', controller: ctrl, hint: '0', allowDecimal: true),
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
    if (value == null || value <= 0 || r.invoiceId == 0) return;
    await InvoiceRepo.applyDiscount(r.invoiceId, percent: value);
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

  /// کسر قلم از سند — بازطراحی صندوق (بند ۲۴)
  Future<void> _removeItem(_CashRow r) async {
    final items = await TicketItemRepo.byTicket(r.ticket.id!);
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قلمی برای کسر ثبت نشده است')));
      return;
    }
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('کسر قلم از سند'),
          content: SizedBox(
            width: 340,
            height: 280,
            child: ListView(
              children: [
                for (final it in items)
                  ListTile(
                    dense: true,
                    title: Text(it.description),
                    subtitle: Text(
                        '${toPersianDigits('${it.qty}')} × ${money(it.price)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete,
                          size: 18, color: Colors.red),
                      onPressed: () => Navigator.pop(ctx, it.id),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await TicketItemRepo.delete(selected);
    await InvoiceRepo.refreshForTicket(r.ticket.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('قلم کسر و فاکتور به‌روز شد')));
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
        onRowTap: (r) => _openSettleSheet(r),
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
            // بند ۱۰.۷۱ — چاپ/PDF رسید از لیست صندوق
            IconButton(
              tooltip: 'چاپ/PDF رسید',
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              onPressed: () => printTicketReceipt(context, r.ticket),
            ),
            if (!r.settled) ...[
              IconButton(
                tooltip: 'فرم تسویه (بند ۲۴)',
                icon: const Icon(Icons.payments, size: 18),
                onPressed: () => _openSettleSheet(r),
              ),
              IconButton(
                tooltip: 'تخفیف نقدی',
                icon: const Icon(Icons.money_off, size: 18),
                onPressed: () => _discountAmount(r),
              ),
              IconButton(
                tooltip: 'تخفیف درصدی',
                icon: const Icon(Icons.percent, size: 18),
                onPressed: () => _discountPercent(r),
              ),
              IconButton(
                tooltip: 'افزودن قلم',
                icon: const Icon(Icons.playlist_add, size: 18),
                onPressed: () => _addItem(r),
              ),
              IconButton(
                tooltip: 'کسر قلم',
                icon: const Icon(Icons.playlist_remove, size: 18),
                onPressed: () => _removeItem(r),
              ),
            ] else
              const Icon(Icons.check_circle, size: 18, color: Colors.green),
          ],
        ),
      ),
    );
  }
}
