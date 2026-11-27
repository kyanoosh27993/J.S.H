/// صفحه سفارشات — فاز ۵ (بند ۱۲)
/// لیست همه سفارشات پذیرش‌شده با کلیه جزئیات؛ صدور پیش‌فاکتور برای سفارشات
/// قبل از تحویل و فاکتور فروش برای تحویل‌شده‌ها؛ جستجو/فیلتر؛ QR سند؛
/// باز کردن سند با تایپ شماره (بند ۶ جدید).
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/data_table_pro.dart';
import '../../shared/widgets/qr_box.dart';
import '../tickets/ticket_detail.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool loading = true;
  List<Ticket> tickets = [];
  Map<int, String> customerNames = {};
  Map<int, Map<String, Object?>> invoicesByTicket = {};

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
      debugPrint('orders _load error: $e');
    }
  }

  Future<void> _loadData() async {
    final ts = await TicketRepo.all();
    final cNames = await CustomerRepo.nameMap();
    final invoices = await InvoiceRepo.allByTicketMap();
    if (!mounted) return;
    setState(() {
      tickets = ts;
      customerNames = cNames;
      invoicesByTicket = invoices;
      loading = false;
    });
  }

  /// صدور سند — پیش‌فاکتور برای قبل از تحویل، فاکتور فروش برای تحویل‌شده (بند ۱۲)
  Future<void> _issue(Ticket t) async {
    final me = AppSession.I.currentUser;
    if (!me!.can('action.invoice.edit')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی صدور فاکتور برای شما مجاز نیست'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final isDelivered = t.status == TicketStatus.delivered;
    final kind = isDelivered ? InvoiceRepo.kindFinal : InvoiceRepo.kindPre;
    final id = await InvoiceRepo.createFromTicket(ticket: t, kind: kind);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isDelivered
          ? 'فاکتور فروش صادر شد (شناسه ${toPersianDigits('$id')})'
          : 'پیش‌فاکتور صادر شد (شناسه ${toPersianDigits('$id')})'),
    ));
    _load();
  }

  /// باز کردن سند با تایپ شماره — بند ۶ جدید
  Future<void> _lookupByNumber() async {
    final ctrl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('باز کردن سند با شماره'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'شماره فاکتور یا کد سفارش (بند ۶ جدید)',
              hintText: 'مثلاً 14050905-0001 یا RCP-20261126-001',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('باز کردن')),
          ],
        ),
      ),
    );
    if (q == null || q.trim().isEmpty) return;
    final invoice = await InvoiceRepo.findByNumberOrCode(q);
    if (!mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('سندی با شماره «${toPersianDigits(q.trim())}» یافت نشد'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final ticketId = invoice['ticket_id'] as int;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketDetailPage(ticketId: ticketId),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppSession.I.currentUser;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('سفارشات پذیرش‌شده',
                  style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('به‌روزرسانی'),
              ),
              OutlinedButton.icon(
                onPressed: _lookupByNumber,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('باز کردن با شماره / QR'),
              ),
              AppText(
                'کاربر: ${me?.bestName ?? '-'}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : tickets.isEmpty
                    ? const Center(child: Text('سفارشی ثبت نشده است'))
                    : SingleChildScrollView(
                        child: DataTablePro<Ticket>(
                          rows: tickets,
                          tableId: 'orders',
                          searchIndex: (t) =>
                              '${t.code} ${customerNames[t.customerId] ?? ''}',
                          onRowTap: (t) async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TicketDetailPage(ticketId: t.id!),
                              ),
                            );
                            _load();
                          },
                          columns: [
                            ProColumn<Ticket>(
                              label: 'کد سفارش',
                              display: (t) => t.code,
                              width: 150,
                            ),
                            ProColumn<Ticket>(
                              label: 'مشتری',
                              display: (t) =>
                                  customerNames[t.customerId] ?? '-',
                              width: 150,
                              filterable: true,
                            ),
                            ProColumn<Ticket>(
                              label: 'وضعیت',
                              display: (t) => statusLabel(t.status),
                              width: 100,
                              filterable: true,
                            ),
                            ProColumn<Ticket>(
                              label: 'پذیرش',
                              display: (t) => shamsiDate(t.intakeDate),
                              width: 100,
                            ),
                            ProColumn<Ticket>(
                              label: 'موعد',
                              display: (t) => t.dueUnknown
                                  ? 'بعد از بررسی'
                                  : shamsiDate(t.dueDate),
                              width: 100,
                            ),
                            ProColumn<Ticket>(
                              label: 'سند',
                              display: (t) {
                                final inv = invoicesByTicket[t.id];
                                if (inv == null) return '—';
                                return '${(inv['kind'] ?? '') == InvoiceRepo.kindFinal ? 'فاکتور' : 'پیش‌فاکتور'} ${toPersianDigits((inv['number'] ?? '') as String)}';
                              },
                              width: 190,
                            ),
                          ],
                          rowAction: (t) => Wrap(
                            spacing: 6,
                            children: [
                              QrBox(
                                  data:
                                      '${t.code} ${(invoicesByTicket[t.id]?['number'] ?? '')}'),
                              if (me?.can('action.invoice.edit') ?? false)
                                IconButton(
                                  tooltip: t.status == TicketStatus.delivered
                                      ? 'صدور فاکتور فروش'
                                      : 'صدور پیش‌فاکتور',
                                  icon: Icon(
                                    t.status == TicketStatus.delivered
                                        ? Icons.receipt
                                        : Icons.request_quote_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => _issue(t),
                                ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
