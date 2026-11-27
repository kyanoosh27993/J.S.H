/// کارتابل تعمیرات — بازطراحی کامل فاز ۳ (بند ۱۱)
/// نمایش لیستی رنگی به‌جای کانبان عریض؛ اسکرول کامل عمودی + جستجو + فیلتر
/// وضعیت/مسئول؛ تغییر وضعیت با کاربر و دلیل (فاز ۲)؛ تحویل با تاییدیه و
/// تسویه (بند ۱۱)؛ برگشت وضعیت فقط توسط تغییردهندهٔ آخر؛ تاریخچه هر سفارش.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/delivery_service.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../tickets/ticket_detail.dart';

/// رنگ هر وضعیت — کارتابل لیستی رنگی (بند ۱۱)
class StatusStyle {
  static const Map<String, Color> colors = {
    TicketStatus.intake: Color(0xFF3B82F6), // آبی
    TicketStatus.diagnosis: Color(0xFF8B5CF6), // بنفش
    TicketStatus.waitingPart: Color(0xFFF59E0B), // کهربایی
    TicketStatus.repairing: Color(0xFFEF4444), // قرمز
    TicketStatus.testing: Color(0xFF14B8A6), // سبزآبی
    TicketStatus.ready: Color(0xFF22C55E), // سبز
    TicketStatus.delivered: Color(0xFF6B7280), // خاکستری
  };
  static Color of(String status) => colors[status] ?? Colors.blueGrey;
}

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  List<Ticket> all = [];
  Map<int, String> userNames = {};
  Map<int, String> customerNames = {};
  Map<int, Map<String, Object?>> lastLog = {};
  Map<int, int> remaining = {};
  String query = '';
  String statusFilter = 'all';
  int? userFilter;
  bool loading = true;

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
      debugPrint('board _load error: $e');
    }
  }

  Future<void> _loadData() async {
    final tickets = await TicketRepo.all();
    final names = <int, String>{};
    for (final u in await UserRepo.list()) {
      final dn = (u['display_name'] ?? '') as String;
      names[u['id'] as int] =
          dn.isEmpty ? (u['username'] ?? '') as String : dn;
    }
    final cNames = await CustomerRepo.nameMap();
    final last = <int, Map<String, Object?>>{};
    final rem = <int, int>{};
    for (final t in tickets) {
      final log = await TicketRepo.statusLog(t.id!);
      if (log.isNotEmpty) last[t.id!] = log.last;
      try {
        rem[t.id!] = await DeliveryService.remainingOf(t);
      } catch (_) {
        rem[t.id!] = 0;
      }
    }
    if (!mounted) return;
    setState(() {
      all = tickets;
      userNames = names;
      customerNames = cNames;
      lastLog = last;
      remaining = rem;
      loading = false;
    });
  }

  bool _canTransition(String from, String to) {
    final me = AppSession.I.currentUser;
    if (me == null) return false;
    return me.can(PermTransitions.keyFor(from, to));
  }

  List<Ticket> get _filtered {
    var out = all;
    if (statusFilter != 'all') {
      out = out.where((t) => t.status == statusFilter).toList();
    }
    if (userFilter != null) {
      out = out.where((t) => t.assignedTo == userFilter).toList();
    }
    if (query.trim().isNotEmpty) {
      final q = toEnglishDigits(query.trim()).toLowerCase();
      out = out.where((t) {
        final hay =
            '${t.code} ${customerNames[t.customerId] ?? ''}'.toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    // بازها اول، جدیدترین اول
    out.sort((a, b) {
      final aDone = a.status == TicketStatus.delivered ? 1 : 0;
      final bDone = b.status == TicketStatus.delivered ? 1 : 0;
      if (aDone != bDone) return aDone - bDone;
      return b.id!.compareTo(a.id!);
    });
    return out;
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
            // سربرگ — روی صفحه باریک، فقط عنوان + به‌روزرسانی (بدون سرریز)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('کارتابل تعمیرات',
                    style: Theme.of(context).textTheme.titleLarge),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('به‌روزرسانی'),
                ),
                AppText(
                  'کاربر جاری: ${AppSession.I.currentUser?.bestName ?? '-'}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // نوار جستجو و فیلتر — همه در یک ردیف با اسکرول افقی روی موبایل
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 18),
                        labelText: 'جستجو (شماره سفارش)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _statusFilterDropdown(),
                  const SizedBox(width: 10),
                  _userFilterDropdown(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(
                          child: Text('سفارشی با این فیلترها نیست'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) =>
                              _row(context, _filtered[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusFilterDropdown() {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        initialValue: statusFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'وضعیت',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: [
          const DropdownMenuItem(value: 'all', child: Text('همه وضعیت‌ها')),
          for (final s in TicketStatus.order)
            DropdownMenuItem(value: s, child: Text(statusLabel(s))),
        ],
        onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
        isDense: true,
      ),
    );
  }

  Widget _userFilterDropdown() {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<int?>(
        initialValue: userFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'مسئول کار',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('همه کاربران')),
          for (final e in userNames.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => userFilter = v),
        isDense: true,
      ),
    );
  }

  // ── ردیف لیستی رنگی ──
  Widget _row(BuildContext context, Ticket t) {
    final color = StatusStyle.of(t.status);
    final log = lastLog[t.id];
    final logTime = log != null && (log['created_at'] ?? '') != ''
        ? shamsiDateTime(
            DateTime.tryParse(log['created_at'] as String) ?? DateTime.now())
        : '';
    final assignee = t.assignedTo != null
        ? (userNames[t.assignedTo] ?? 'کاربر ${toPersianDigits('${t.assignedTo}')}')
        : 'واگذار نشده';
    final rem = remaining[t.id] ?? 0;
    final overdue = t.status != TicketStatus.delivered &&
        t.dueDate.isBefore(DateTime.now());
    final customer = customerNames[t.customerId] ?? '...';
    return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // نوار رنگی وضعیت
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(toPersianDigits(t.code),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          // چیپ رنگی وضعیت — بند ۱۱
                          Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: color.withValues(alpha: 0.14),
                            label: Text(statusLabel(t.status),
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: color,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const Spacer(),
                          if (overdue)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.red.withValues(alpha: 0.1),
                              label: const Text('موعد گذشته',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.red)),
                            ),
                          Text(shamsiDate(t.dueDate),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: overdue
                                      ? Colors.red
                                      : Colors.blueGrey)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 14,
                        runSpacing: 2,
                        children: [
                          Text('مشتری: $customer',
                              style: const TextStyle(fontSize: 12.5)),
                          Text('مسئول: $assignee',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.deepOrange)),
                          if (rem > 0)
                            Text('باقیمانده: ${moneyToman(rem)}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.red)),
                        ],
                      ),
                      if (logTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('آخرین تغییر: $logTime',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Theme.of(context).colorScheme.outline)),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (t.status == TicketStatus.ready)
                            _deliverButton(t)
                          else ...[
                            Tooltip(
                              message: 'مرحله قبل — فقط تغییردهندهٔ آخر',
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.undo, size: 15),
                                label: const Text('مرحله قبل', style: TextStyle(fontSize: 11.5)),
                                onPressed: () => _advance(t, false),
                              ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.redo, size: 15),
                              label: Text('مرحله بعد',
                                  style: const TextStyle(fontSize: 11.5)),
                              onPressed: () => _advance(t, true),
                            ),
                          ],
                          IconButton(
                            tooltip: 'تاریخچه وضعیت‌ها',
                            icon: const Icon(Icons.history, size: 18),
                            onPressed: () => _historyDialog(t),
                          ),
                          IconButton(
                            tooltip: 'جزئیات سفارش',
                            icon: const Icon(Icons.open_in_new, size: 18),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TicketDetailPage(ticketId: t.id!),
                                ),
                              );
                              _load();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }

  Widget _deliverButton(Ticket t) {
    return FilledButton.icon(
      icon: const Icon(Icons.local_shipping, size: 16),
      label: const Text('تحویل با تاییدیه', style: TextStyle(fontSize: 11.5)),
      onPressed: () => _deliverFlow(t),
    );
  }

  // ── جریان تحویل با تاییدیه و تسویه (بند ۱۱) ──
  Future<void> _deliverFlow(Ticket t) async {
    final rem = await DeliveryService.remainingOf(t);
    if (!mounted) return;
    final choice = await showDialog<DeliveryDecision>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تاییدیه تحویل ${toPersianDigits(t.code)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rem > 0
                    ? 'باقیمانده تسویه این سفارش: ${moneyToman(rem)}'
                    : 'حساب این سفارش کامل تسویه شده است.',
                style: const TextStyle(fontSize: 13.5, height: 1.7),
              ),
              if (rem > 0) ...[
                const SizedBox(height: 8),
                const Text(
                  'با تحویل، پیش‌فاکتور این سفارش به فاکتور قطعی تبدیل می‌شود.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            if (rem > 0) ...[
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
            ] else
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, DeliveryDecision.settleAndDeliver),
                child: const Text('تایید و تحویل'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final result =
        await DeliveryService.deliver(t, decision: choice);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: result.ok ? null : Colors.red,
    ));
    _load();
  }

  // ── تغییر وضعیت رو به جلو / برگشت (فاز ۲ + بند ۱۱) ──
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
      final reason = await _reasonDialog('برگشت به مرحله «${statusLabel(to)}»');
      if (reason == null || reason.trim().isEmpty) return;
      await TicketRepo.changeStatus(t.id!, to,
          userId: me?.id ?? 0, reason: reason.trim());
    }
    await _load();
  }

  /// گفت‌وگوی تغییر وضعیت رو به جلو — دلیل + واگذاری
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
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }

  /// تاریخچه کامل تغییر وضعیت‌ها با کاربر و دلیل (بند ۱۱)
  Future<void> _historyDialog(Ticket t) async {
    final log = await TicketRepo.statusLog(t.id!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تاریخچه ${toPersianDigits(t.code)}'),
          content: SizedBox(
            width: 420,
            child: log.isEmpty
                ? const Text('تاریخچه‌ای ثبت نشده است')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: log.length,
                    itemBuilder: (_, i) {
                      final e = log[i];
                      final uid = e['user_id'] as int?;
                      final reason = ((e['reason'] ?? '') as String).trim();
                      final note = ((e['note'] ?? '') as String).trim();
                      final from = (e['from_status'] ?? '') as String;
                      final to =
                          (e['to_status'] ?? (e['status'] ?? '')) as String;
                      final hasFrom = from.isNotEmpty && from != to;
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.flag,
                            size: 18,
                            color: StatusStyle.of(to)),
                        title: Text(hasFrom
                            ? '${statusLabel(from)} ← ${statusLabel(to)}'
                            : statusLabel(to),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          [
                            if (uid != null && uid != 0)
                              'کاربر: ${userNames[uid] ?? uid}',
                            if (reason.isNotEmpty) 'دلیل: $reason',
                            if (note.isNotEmpty) note,
                            (e['created_at'] ?? '') as String,
                          ].join(' — '),
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بستن')),
          ],
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
