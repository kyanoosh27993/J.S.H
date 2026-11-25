/// فاکتورها — جدول هوشمند سورت‌پذیر با جمع (قواعد ۵، ۶، ۱۱)
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/utils.dart';
import '../../shared/widgets/data_table_pro.dart';
import '../tickets/ticket_detail.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoiceRow {
  final Ticket ticket;
  final String customerName;
  final int total;
  final int paid;
  final int remaining;
  _InvoiceRow(this.ticket, this.customerName, this.total, this.paid,
      this.remaining);
}

class _InvoicesPageState extends State<InvoicesPage> {
  List<_InvoiceRow> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final itemSums = await TicketItemRepo.sumsForAllTickets();
    final paidSums = await PaymentRepo.paidSumForAll();
    final out = <_InvoiceRow>[];
    for (final t in tickets) {
      final c = await CustomerRepo.byId(t.customerId);
      final itemsSum = itemSums[t.id] ?? 0;
      final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
      final paid = paidSums[t.id] ?? 0;
      out.add(_InvoiceRow(t, c?.name ?? '-', total, paid, total - paid));
    }
    if (!mounted) return;
    setState(() {
      rows = out;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('فاکتورها و وضعیت پرداخت',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 10),
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
            const SizedBox(height: 10),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? const Center(child: Text('سفارشی ثبت نشده است'))
                      : SingleChildScrollView(
                          child: DataTablePro<_InvoiceRow>(
                            rows: rows,
                            tableId: 'invoices',
                            searchIndex: (r) =>
                                '${r.ticket.code} ${r.customerName}',
                            onRowTap: (r) {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    TicketDetailPage(ticketId: r.ticket.id!),
                              ));
                            },
                            columns: [
                              ProColumn<_InvoiceRow>(
                                label: 'شماره سفارش',
                                display: (r) => r.ticket.code,
                                width: 150,
                              ),
                              ProColumn<_InvoiceRow>(
                                label: 'مشتری',
                                display: (r) => r.customerName,
                                width: 170,
                                filterable: true,
                              ),
                              ProColumn<_InvoiceRow>(
                                label: 'وضعیت',
                                display: (r) => statusLabel(r.ticket.status),
                                width: 110,
                                filterable: true,
                              ),
                              ProColumn<_InvoiceRow>(
                                label: 'جمع فاکتور',
                                display: (r) => money(r.total),
                                width: 130,
                                numeric: (r) => r.total,
                              ),
                              ProColumn<_InvoiceRow>(
                                label: 'پرداخت‌شده',
                                display: (r) => money(r.paid),
                                width: 130,
                                numeric: (r) => r.paid,
                              ),
                              ProColumn<_InvoiceRow>(
                                label: 'باقیمانده',
                                display: (r) => money(r.remaining),
                                width: 130,
                                numeric: (r) => r.remaining,
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
}
