/// فاکتورها — نمایش فاکتور هر سفارش (تولید خودکار از اقلام + پرداخت‌ها)
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/utils.dart';
import '../tickets/ticket_detail.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final out = <Map<String, Object?>>[];
    for (final t in tickets) {
      final items = await TicketItemRepo.byTicket(t.id!);
      final itemsSum = items.fold<int>(0, (s, i) => s + i.price * i.qty);
      final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
      final paid = await PaymentRepo.paidSum(t.id!);
      final c = await CustomerRepo.byId(t.customerId);
      out.add({
        'ticket': t,
        'customer_name': c?.name ?? '-',
        'total': total,
        'paid': paid,
        'remaining': total - paid,
      });
    }
    if (mounted) setState(() => rows = out);
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
            Text('فاکتورها و وضعیت پرداخت',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('سفارشی ثبت نشده است'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final t = r['ticket'] as Ticket;
                        final rem = r['remaining'] as int;
                        return Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => TicketDetailPage(ticketId: t.id!),
                              ));
                            },
                            title: Text('${r['customer_name']} — ${toPersianDigits(t.code)}'),
                            subtitle: Text(
                                'جمع: ${moneyToman(r['total'] as int)} — پرداخت‌شده: ${moneyToman(r['paid'] as int)}'),
                            trailing: Text(
                              rem > 0 ? 'بدهی: ${moneyToman(rem)}' : 'تسویه کامل',
                              style: TextStyle(
                                color: rem > 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
