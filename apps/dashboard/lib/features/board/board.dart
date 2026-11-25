/// کارتابل کانبان تعمیرات (S-01) — جابه‌جایی سفارش بین مراحل
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/utils.dart';
import '../../core/warranty.dart';
import '../tickets/ticket_detail.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  Map<String, List<Ticket>> columns = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    if (!mounted) return;
    setState(() {
      columns = {for (final s in TicketStatus.order) s: <Ticket>[]};
      for (final t in tickets) {
        columns.putIfAbsent(t.status, () => []).add(t);
      }
    });
  }

  Future<void> _advance(Ticket t, bool forward) async {
    final idx = TicketStatus.order.indexOf(t.status);
    final next = idx + (forward ? 1 : -1);
    if (next < 0 || next >= TicketStatus.order.length) return;
    await TicketRepo.changeStatus(t.id!, TicketStatus.order[next]);
    // فاز ۲: گارانتی خودکار هنگام تحویل
    if (TicketStatus.order[next] == 'delivered') {
      try {
        final months = await WarrantyRepo.defaultMonths();
        await WarrantyRepo.upsertForTicket(t.id!, months);
      } catch (_) {}
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('کارتابل تعمیرات',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('به‌روزرسانی'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final status in TicketStatus.order)
                    _column(context, status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(BuildContext context, String status) {
    final cards = columns[status] ?? [];
    final countFa = toPersianDigits('${cards.length}');
    return Container(
      width: 265,
      margin: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Text('${statusLabel(status)} ($countFa)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
              ],
            ),
          ),
          Expanded(
            child: cards.isEmpty
                ? const Center(child: Text('—', style: TextStyle(color: Colors.grey)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: cards.map((t) => _card(context, t)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Ticket t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: t.id!),
          ));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(t.code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  Text(shamsiDate(t.dueDate), style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              ),
              const SizedBox(height: 4),
              FutureBuilder<Customer?>(
                future: CustomerRepo.byId(t.customerId),
                builder: (_, snap) => Text(
                  snap.hasData ? snap.data!.name : '...',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'مرحله قبل',
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    onPressed: () => _advance(t, false),
                  ),
                  Text(statusLabel(t.status),
                      style: TextStyle(fontSize: 11.5, color: Colors.deepOrange.shade700)),
                  IconButton(
                    tooltip: 'مرحله بعد',
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: () => _advance(t, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
