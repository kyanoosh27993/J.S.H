/// CRM مشتریان (F-07) — جستجو، افزودن/ویرایش، تاریخچه سفارش‌ها
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/utils.dart';
import '../tickets/ticket_detail.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<Customer> list = [];
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await CustomerRepo.search(q);
    if (mounted) setState(() => list = l);
  }

  Future<void> _openEditor([Customer? c]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerDialog(customer: c),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'جستجو با نام، تلفن یا کد ملی',
                    ),
                    onChanged: (v) {
                      q = v;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.person_add),
                  label: const Text('مشتری جدید'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('مشتری‌ای ثبت نشده است'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text(c.name.isNotEmpty ? c.name[0] : '?')),
                            title: Text(c.name),
                            subtitle: Text(
                                '${toPersianDigits(c.phone)}   |   کد ملی: ${toPersianDigits(c.nationalId)}'
                                '${c.tag.isEmpty ? '' : '   |   ${c.tag}'}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _openEditor(c),
                            ),
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CustomerHistoryPage(customerId: c.id!),
                              ));
                            },
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

class _CustomerDialog extends StatefulWidget {
  final Customer? customer;
  const _CustomerDialog({this.customer});

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final name = TextEditingController(text: widget.customer?.name ?? '');
  late final father = TextEditingController(text: widget.customer?.fatherName ?? '');
  late final nid = TextEditingController(text: widget.customer?.nationalId ?? '');
  late final phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final address = TextEditingController(text: widget.customer?.address ?? '');
  late final tag = TextEditingController(text: widget.customer?.tag ?? '');

  @override
  void dispose() {
    for (final c in [name, father, nid, phone, address, tag]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'مشتری جدید' : 'ویرایش مشتری'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(name, 'نام و نام خانوادگی *'),
              _f(father, 'نام پدر'),
              _f(nid, 'شماره ملی'),
              _f(phone, 'تلفن همراه'),
              _f(address, 'آدرس'),
              _f(tag, 'برچسب (مثال: مشتری قدیمی)'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty) return;
            final c = widget.customer ?? Customer(name: name.text.trim());
            c
              ..name = name.text.trim()
              ..fatherName = father.text.trim()
              ..nationalId = nid.text.trim()
              ..phone = phone.text.trim()
              ..address = address.text.trim()
              ..tag = tag.text.trim();
            if (c.id == null) {
              await CustomerRepo.insert(c);
            } else {
              await CustomerRepo.update(c);
            }
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('ذخیره'),
        ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(controller: c, decoration: InputDecoration(labelText: label)),
      );
}

/// تاریخچه مشتری — بخشی از CRM کامل
class CustomerHistoryPage extends StatelessWidget {
  final int customerId;
  const CustomerHistoryPage({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تاریخچه مشتری')),
        body: FutureBuilder<List<dynamic>>(
          future: _load(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final customer = snap.data![0] as Customer?;
            final tickets = snap.data![1] as List<Ticket>;
            if (customer == null) return const Center(child: Text('یافت نشد'));
            final countFa = toPersianDigits('${tickets.length}');
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(customer.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text('تلفن: ${toPersianDigits(customer.phone)} — کد ملی: ${toPersianDigits(customer.nationalId)}'),
                Text('آدرس: ${customer.address}'),
                const Divider(height: 24),
                Text('سفارش‌ها ($countFa)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ...tickets.map((t) => ListTile(
                      title: Text('${t.code} — ${statusLabel(t.status)}'),
                      subtitle: Text('موعد تحویل: ${shamsiDate(t.dueDate)} — بیعانه: ${moneyToman(t.depositAmount)}'),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TicketDetailPage(ticketId: t.id!),
                        ));
                      },
                    )),
                if (tickets.isEmpty) const Text('هنوز سفارشی ثبت نشده است'),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<List<dynamic>> _load() async {
    final c = await CustomerRepo.byId(customerId);
    final dbTickets = await TicketRepo.all();
    final t = dbTickets.where((x) => x.customerId == customerId).toList();
    return [c, t];
  }
}
