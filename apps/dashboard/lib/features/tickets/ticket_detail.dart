/// جزئیات سفارش — قطعات/خدمات، پرداخت‌ها، فاکتور، تحویل با اقرارنامه
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/delivery_service.dart';
import '../../core/services/reminder_service.dart';
import '../../core/utils.dart';

class TicketDetailPage extends StatefulWidget {
  final int ticketId;
  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  Ticket? t;
  Customer? c;
  Device? d;
  List<TicketItem> items = [];
  List<Payment> payments = [];
  List<Map<String, Object?>> log = [];

  final itemDesc = TextEditingController();
  final itemQty = TextEditingController(text: '1');
  final itemPrice = TextEditingController();
  String itemKind = 'service';
  final warrantyMonths = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [itemDesc, itemQty, itemPrice, warrantyMonths]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final ticket = await TicketRepo.byId(widget.ticketId);
    if (ticket == null) return;
    final customer = await CustomerRepo.byId(ticket.customerId);
    final device = await DeviceRepo.byId(ticket.deviceId);
    final i = await TicketItemRepo.byTicket(widget.ticketId);
    final p = await PaymentRepo.byTicket(widget.ticketId);
    final l = await TicketRepo.statusLog(widget.ticketId);
    if (!mounted) return;
    setState(() {
      t = ticket;
      c = customer;
      d = device;
      items = i;
      payments = p;
      log = l;
    });
  }

  int get itemsSum => items.fold<int>(0, (s, i) => s + i.price * i.qty);
  int get paid => payments.fold<int>(0, (s, p) => s + p.amount);
  int get total => itemsSum > 0 ? itemsSum : (t?.estimateAmount ?? 0);
  int get remaining => total - paid;

  Future<void> _addItem() async {
    final price = int.tryParse(toEnglishDigits(itemPrice.text)) ?? 0;
    final qty = int.tryParse(toEnglishDigits(itemQty.text)) ?? 1;
    if (itemDesc.text.trim().isEmpty || price <= 0) return;
    await TicketItemRepo.insert(TicketItem(
      ticketId: widget.ticketId,
      kind: itemKind,
      description: itemDesc.text.trim(),
      qty: qty,
      price: price,
      warrantyMonths: int.tryParse(toEnglishDigits(warrantyMonths.text)) ?? 0,
    ));
    itemDesc.clear();
    itemPrice.clear();
    itemQty.text = '1';
    _load();
  }

  Future<void> _addPayment(String kind) async {
    final ctrl = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kind == 'deposit' ? 'دریافت بیعانه' : 'دریافت پرداخت'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(toEnglishDigits(ctrl.text)) ?? 0),
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    // فاز ۲ — ثبت کاربر وصول‌کننده (بند ۸: گزارش عملکرد)
    await PaymentRepo.insert(Payment(
      ticketId: widget.ticketId,
      amount: amount,
      kind: kind,
      userId: AppSession.I.currentUser?.id,
    ));
    _load();
  }

  Future<void> _deliver() async {
    // فاز ۳ (بند ۱۱): تحویل با تاییدیه و تسویه — پیش‌فاکتور → فاکتور
    final rem = await DeliveryService.remainingOf(t!);
    if (!mounted) return;
    DeliveryDecision? choice;
    if (rem > 0) {
      choice = await showDialog<DeliveryDecision>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تاییدیه تحویل'),
            content: Text(
                'باقیمانده تسویه: ${moneyToman(rem)}\n\n'
                'با تحویل، پیش‌فاکتور به فاکتور قطعی تبدیل می‌شود.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('انصراف')),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, DeliveryDecision.deliverWithDebt),
                child: const Text('تحویل با بدهی (تایید می‌کنم)',
                    style: TextStyle(color: Colors.red)),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, DeliveryDecision.settleAndDeliver),
                child: const Text('تسویه کامل و تحویل'),
              ),
            ],
          ),
        ),
      );
    } else {
      choice = DeliveryDecision.settleAndDeliver;
    }
    if (choice == null) return;
    final result = await DeliveryService.deliver(t!, decision: choice);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = t;
    if (ticket == null) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text('سفارش ${toPersianDigits(ticket.code)}')),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: ListView(
            children: [
              Wrap(spacing: 18, runSpacing: 4, children: [
                Text('مشتری: ${c?.name ?? '-'}'),
                Text('دستگاه: ${d?.model ?? '-'} — سریال: ${toPersianDigits(d?.serial ?? '')}'),
                Text('موعد: ${shamsiDateTime(DateTime(
                      ticket.dueDate.year,
                      ticket.dueDate.month,
                      ticket.dueDate.day,
                      int.tryParse(ticket.dueTime.split(':').first) ?? 18,
                    ))}'),
                Chip(label: Text(statusLabel(ticket.status))),
              ]),
              const Divider(height: 22),
              Text('خلاصه مالی', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              _kv('برآورد اولیه اعلامی', moneyToman(ticket.estimateAmount)),
              _kv('مبلغ افزوده نسبت به برآورد', moneyToman(ReminderService.addedOf(ticket, items))),
              _kv('جمع قطعات و خدمات', moneyToman(total)),
              _kv('پرداخت‌شده', moneyToman(paid)),
              _kv('باقیمانده قابل وصول', moneyToman(remaining), highlight: remaining > 0),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton.icon(
                  onPressed: () => _addPayment('final'),
                  icon: const Icon(Icons.payment),
                  label: const Text('دریافت پرداخت'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: ticket.status == TicketStatus.delivered ? null : _deliver,
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('تحویل + اقرارنامه'),
                ),
              ]),
              const Divider(height: 24),
              Text('قطعات تعویض‌شده و خدمات', style: Theme.of(context).textTheme.titleMedium),
              ...items.map(_itemTile),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('هنوز قلمی ثبت نشده است'),
                ),
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(children: [
                    Row(children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'part', label: Text('قطعه')),
                          ButtonSegment(value: 'service', label: Text('خدمت')),
                        ],
                        selected: {itemKind},
                        onSelectionChanged: (v) => setState(() => itemKind = v.first),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: itemDesc,
                          decoration: const InputDecoration(labelText: 'شرح قلم *'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(
                        controller: itemQty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'تعداد'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: itemPrice,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'قیمت واحد (تومان) *'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: warrantyMonths,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'گارانتی (ماه)'),
                      )),
                      IconButton.filled(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add),
                        tooltip: 'افزودن قلم',
                      ),
                    ]),
                  ]),
                ),
              ),
              const Divider(height: 24),
              Text('تاریخچه مراحل', style: Theme.of(context).textTheme.titleMedium),
              ...log.map((e) {
                // فاز ۲ — نمایش کاربر و دلیل هر تغییر (بند ۸)
                final uid = e['user_id'] as int?;
                final reason = ((e['reason'] ?? '') as String).trim();
                final note = ((e['note'] ?? '') as String).trim();
                final from = (e['from_status'] ?? '') as String;
                final to = (e['to_status'] ?? (e['status'] ?? '')) as String;
                final hasFrom = from.isNotEmpty && from != to;
                return FutureBuilder<String>(
                  future: uid == null || uid == 0
                      ? Future.value('سیستم')
                      : UserRepo.displayNameOf(uid),
                  builder: (_, snap) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.flag, size: 18),
                    title: Text(hasFrom
                        ? '${statusLabel(from)} ← ${statusLabel(to)}'
                        : statusLabel(to)),
                    subtitle: Text(
                      [
                        'کاربر: ${snap.data ?? '...'}',
                        if (reason.isNotEmpty) 'دلیل: $reason',
                        if (note.isNotEmpty) note,
                        (e['created_at'] ?? '') as String,
                      ].join(' — '),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemTile(TicketItem i) {
    return ListTile(
      dense: true,
      leading: Icon(i.kind == 'part' ? Icons.memory : Icons.build, size: 20),
      title: Text('${i.description} × ${toPersianDigits('${i.qty}')}'),
      subtitle: i.warrantyMonths > 0
          ? Text('گارانتی: ${toPersianDigits('${i.warrantyMonths}')} ماه',
              style: const TextStyle(color: Colors.green))
          : null,
      trailing: Text(moneyToman(i.price * i.qty)),
    );
  }

  Widget _kv(String k, String v, {bool highlight = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 200, child: Text(k, style: const TextStyle(color: Colors.blueGrey, fontSize: 13))),
            Text(v,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: highlight ? Colors.red : null,
                )),
          ],
        ),
      );
}
