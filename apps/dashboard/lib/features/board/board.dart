/// کارتابل کانبان تعمیرات (S-01) — جابه‌جایی سفارش بین مراحل
/// فاز ۲ (بند ۸): تغییر وضعیت با ثبت کاربر و دلیل، واگذاری سفارش به کاربر،
/// قاعده برگشت (فقط کاربری که آخرین تغییر را داده یا مدیر/سازنده) و
/// نمایش مسئول فعلی هر سفارش روی کارت.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils.dart';
import '../../core/warranty.dart';
import '../../shared/widgets/app_text.dart';
import '../tickets/ticket_detail.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  Map<String, List<Ticket>> columns = {};
  Map<int, String> userNames = {};
  Map<int, Map<String, Object?>> lastLog = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final dbUsers = await UserRepo.list();
    final names = <int, String>{};
    for (final u in dbUsers) {
      final dn = (u['display_name'] ?? '') as String;
      names[u['id'] as int] =
          dn.isEmpty ? (u['username'] ?? '') as String : dn;
    }
    // آخرین تغییر وضعیت هر سفارش — برای قاعده برگشت و نمایش زمان
    final last = <int, Map<String, Object?>>{};
    for (final t in tickets) {
      final log = await TicketRepo.statusLog(t.id!);
      if (log.isNotEmpty) last[t.id!] = log.last;
    }
    if (!mounted) return;
    setState(() {
      userNames = names;
      lastLog = last;
      columns = {for (final s in TicketStatus.order) s: <Ticket>[]};
      for (final t in tickets) {
        columns.putIfAbsent(t.status, () => []).add(t);
      }
    });
  }

  /// آیا کاربر جاری اجازه گذار رو به جلو از این مرحله را دارد؟
  bool _canTransition(String from, String to) {
    final me = AppSession.I.currentUser;
    if (me == null) return false;
    return me.can(PermTransitions.keyFor(from, to));
  }

  Future<void> _advance(Ticket t, bool forward) async {
    final idx = TicketStatus.order.indexOf(t.status);
    final next = idx + (forward ? 1 : -1);
    if (next < 0 || next >= TicketStatus.order.length) return;
    final to = TicketStatus.order[next];
    final me = AppSession.I.currentUser;

    if (forward) {
      if (!_canTransition(t.status, to)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'دسترسی تغییر وضعیت از «${statusLabel(t.status)}» به «${statusLabel(to)}» برای شما مجاز نیست'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final result = await _statusDialog(t, to);
      if (result == null) return;
      await TicketRepo.changeStatus(t.id!, to,
          userId: me?.id ?? 0,
          reason: result.reason,
          assignTo: result.assignTo);
    } else {
      // قاعده بند ۸ — برگشت فقط توسط آخرین تغییردهنده (مدیر/سازنده همیشه)
      final allowed = await TicketRepo.canRevert(t.id!, me);
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'برگشت وضعیت فقط توسط کاربری که آخرین تغییر را داده امکان‌پذیر است (یا مدیر/سازنده)'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final reason = await _reasonDialog('برگشت به مرحله «${statusLabel(to)}»',
          required: true);
      if (reason == null || reason.trim().isEmpty) return;
      await TicketRepo.changeStatus(t.id!, to,
          userId: me?.id ?? 0, reason: reason.trim());
    }

    // فاز ۲: گارانتی خودکار هنگام تحویل
    if (to == 'delivered') {
      try {
        final months = await WarrantyRepo.defaultMonths();
        await WarrantyRepo.upsertForTicket(t.id!, months);
      } catch (_) {}
    }
    await _load();
  }

  /// گفت‌وگوی تغییر وضعیت رو به جلو — دلیل (اختیاری) + واگذاری به کاربر
  Future<_StatusResult?> _statusDialog(Ticket t, String to) async {
    final me = AppSession.I.currentUser;
    final canDelegate = me?.can('action.delegation.assign') ?? false;
    int? assignTo = t.assignedTo ?? me?.id;
    final reasonCtrl = TextEditingController();
    final users = (await UserRepo.list())
        .where((u) => ((u['is_active'] ?? 1) as int) == 1)
        .toList();
    if (!mounted) return null;
    return showDialog<_StatusResult>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDState) => AlertDialog(
            title: Text('انتقال به «${statusLabel(to)}»'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سفارش ${toPersianDigits(t.code)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'دلیل / توضیح (در گزارش ثبت می‌شود)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  if (canDelegate) ...[
                    const SizedBox(height: 12),
                    Text('واگذاری کار به',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(ctx).colorScheme.outline)),
                    DropdownButtonFormField<int?>(
                      initialValue: assignTo,
                      items: [
                        for (final u in users)
                          DropdownMenuItem(
                            value: u['id'] as int,
                            child: Text(
                                '${((u['display_name'] ?? '') as String).isEmpty ? u['username'] : u['display_name']}'
                                ' (${u['username']})',
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                      ],
                      onChanged: (v) => setDState(() => assignTo = v),
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('انصراف')),
              FilledButton(
                onPressed: () => Navigator.pop(
                    ctx,
                    _StatusResult(
                        reason: reasonCtrl.text.trim(), assignTo: assignTo)),
                child: const Text('ثبت'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// گفت‌وگوی ثبت دلیل — برای برگشت وضعیت (الزامی، بند ۸)
  Future<String?> _reasonDialog(String title, {bool required = false}) async {
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
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'دلیل (الزامی — در گزارش ثبت می‌شود)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                if (required && ctrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
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
                const Spacer(),
                AppText(
                  'کاربر جاری: ${AppSession.I.currentUser?.bestName ?? '-'}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline),
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
    final log = lastLog[t.id];
    final logTime = log != null && (log['created_at'] ?? '') != ''
        ? shamsiDateTime(DateTime.tryParse(log['created_at'] as String) ?? DateTime.now())
        : '';
    final assignee = t.assignedTo != null
        ? (userNames[t.assignedTo] ?? 'کاربر ${toPersianDigits('${t.assignedTo}')}')
        : null;
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
              if (assignee != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.handyman, size: 13, color: Colors.deepOrange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('مسئول: $assignee',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.deepOrange),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
              if (logTime.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('آخرین تغییر: $logTime',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.outline)),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Tooltip(
                    message: 'مرحله قبل — فقط تغییردهندهٔ آخرین مرحله',
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      onPressed: () => _advance(t, false),
                    ),
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

class _StatusResult {
  final String reason;
  final int? assignTo;
  const _StatusResult({required this.reason, this.assignTo});
}
