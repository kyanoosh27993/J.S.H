/// یادآوری‌ها (F-05) — کارهای امروز با جزئیات مالی + یادآوری‌های در انتظار
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/reminder_service.dart';
import '../../core/utils.dart';
import '../tickets/ticket_detail.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  List<TodayTask> tasks = [];
  List<Reminder> pendingReminders = [];
  int leadDays = ReminderPrefs.defaultLeadDays;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (lead, _) = await ReminderService.loadPrefs();
    final now = DateTime.now();
    final due = await TicketRepo.dueBetween(now, now.add(Duration(days: lead)));
    final out = <TodayTask>[];
    for (final t in due) {
      out.add(await ReminderService.buildTask(t, lead));
    }
    final pending = await ReminderRepo.pendingBefore(
        now.add(const Duration(days: 7)));
    if (!mounted) return;
    setState(() {
      leadDays = lead;
      tasks = out..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
      pendingReminders = pending;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Text('یادآوری‌ها — پنجره ${toPersianDigits('$leadDays')} روز',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('به‌روزرسانی'),
                ),
              ],
            ),
            const Text(
              'در این پنجره، سفارش‌هایی که باید تحویل شوند با بیعانه، مبلغ افزوده نسبت به برآورد اولیه و مجموع قابل وصول نمایش داده می‌شوند.',
              style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
            ),
            const SizedBox(height: 10),
            if (tasks.isEmpty) const Text('در پنجره یادآوری، سفارش در انتظار تحویلی نیست.'),
            ...tasks.map(_taskCard),
            const Divider(height: 28),
            Text('یادآوری‌های ثبت‌شده', style: Theme.of(context).textTheme.titleMedium),
            ...pendingReminders.map((r) => ListTile(
                  leading: const Icon(Icons.alarm),
                  title: Text(r.message.isEmpty ? 'یادآوری سفارش' : r.message),
                  subtitle: Text('زمان: ${shamsiDateTime(r.remindAt)} — وضعیت: ${r.status == 'pending' ? 'در انتظار نمایش' : 'نمایش داده شده'}'),
                )),
            if (pendingReminders.isEmpty) const Text('یادآوری ثبت‌شده‌ای نیست.'),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(TodayTask task) {
    final t = task.ticket;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailPage(ticketId: t.id!),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(
                    backgroundColor: task.daysLeft <= 1 ? Colors.red.shade100 : Colors.amber.shade100,
                    label: Text(task.daysLeft == 0
                        ? 'امروز باید تحویل شود'
                        : '${toPersianDigits('${task.daysLeft}')} روز تا موعد'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${t.code} — ${statusLabel(t.status)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _kv('بیعانه گرفته‌شده', moneyToman(task.deposit)),
                _kv('مبلغ افزوده نسبت به برآورد اولیه', moneyToman(task.addedAmount)),
                _kv('مجموع قابل وصول از مشتری', moneyToman(task.collectable),
                    highlight: task.collectable > 0),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool highlight = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11.5, color: Colors.blueGrey)),
          Text(v,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.red : null,
              )),
        ],
      );
}
