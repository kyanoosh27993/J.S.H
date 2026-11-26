/// یادآوری‌ها (F-05) — فاز ۶ (بند ۱۷)
/// سربرگ ۱: کارهای امروز با جزئیات مالی + یادآوری‌های ثبت‌شده (قابل حذف)
/// سربرگ ۲: گزارش روزانه — همه تغییرات یک روز با خروجی فایل در مسیر دلخواه
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/db/db.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/daily_report_service.dart';
import '../../core/services/reminder_service.dart';
import '../../core/utils.dart';
import '../../shared/widgets/shamsi_date_field.dart';
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
      out.add(await ReminderService.buildTask(t));
    }
    final pending =
        await ReminderRepo.pendingBefore(now.add(const Duration(days: 7)));
    if (!mounted) return;
    setState(() {
      leadDays = lead;
      tasks = out..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
      pendingReminders = pending;
    });
  }

  /// بند ۱۷ — حذف یادآوری از داخل برنامه
  Future<void> _deleteReminder(Reminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف یادآوری'),
        content: Text('یادآوری «${r.message.isEmpty ? 'بی‌متن' : r.message}» حذف شود؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final db = await Db.instance();
    await db.delete('reminders', where: 'id = ?', whereArgs: [r.id]);
    _load();
  }

  @override
  Widget build(BuildContext context) {
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
                  Text('یادآوری‌ها',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('به‌روزرسانی'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const TabBar(
                tabs: [
                  Tab(text: 'پنجره یادآوری'),
                  Tab(text: 'گزارش روزانه تغییرات'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _remindersTab(),
                    const _DailyReportTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _remindersTab() {
    return ListView(
      children: [
        Text(
          'پنجره یادآوری: ${toPersianDigits('$leadDays')} روز — سفارش‌هایی که باید تحویل شوند با بیعانه، مبلغ افزوده و مجموع قابل وصول.',
          style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey),
        ),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          const Text('در پنجره یادآوری، سفارش در انتظار تحویلی نیست.'),
        ...tasks.map(_taskCard),
        const Divider(height: 28),
        Text('یادآوری‌های ثبت‌شده',
            style: Theme.of(context).textTheme.titleMedium),
        ...pendingReminders.map((r) => ListTile(
              leading: const Icon(Icons.alarm),
              title:
                  Text(r.message.isEmpty ? 'یادآوری سفارش' : r.message),
              subtitle: Text(
                  'زمان: ${shamsiDateTime(r.remindAt)} — وضعیت: ${r.status == 'pending' ? 'در انتظار نمایش' : 'نمایش داده شده'}'),
              trailing: IconButton(
                tooltip: 'حذف یادآوری (بند ۱۷)',
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: () => _deleteReminder(r),
              ),
            )),
        if (pendingReminders.isEmpty)
          const Text('یادآوری ثبت‌شده‌ای نیست.'),
      ],
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
                    backgroundColor: task.daysLeft <= 1
                        ? Colors.red.shade100
                        : Colors.amber.shade100,
                    label: Text(
                      task.daysLeft == 0
                          ? 'امروز باید تحویل شود'
                          : task.daysLeft > 0
                              ? '${toPersianDigits('${task.daysLeft}')} روز تا موعد'
                              : '${toPersianDigits('${-task.daysLeft}')} روز از موعد گذشته',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${t.code} — ${statusLabel(t.status)}',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _kv('بیعانه گرفته‌شده', moneyToman(task.deposit)),
                _kv('مبلغ افزوده نسبت به برآورد اولیه',
                    moneyToman(task.addedAmount)),
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
          Text(k,
              style:
                  const TextStyle(fontSize: 11.5, color: Colors.blueGrey)),
          Text(v,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.red : null,
              )),
        ],
      );
}

/// سربرگ گزارش روزانه — بند ۱۷: همه تغییرات روز + خروجی فایل + حذف
class _DailyReportTab extends StatefulWidget {
  const _DailyReportTab();

  @override
  State<_DailyReportTab> createState() => _DailyReportTabState();
}

class _DailyReportTabState extends State<_DailyReportTab> {
  DateTime day = DateTime.now();
  List<DailyReportEntry> entries = [];
  bool loading = false;

  Future<void> _run() async {
    setState(() => loading = true);
    final data = await DailyReportService.eventsOf(day);
    if (!mounted) return;
    setState(() {
      entries = data;
      loading = false;
    });
  }

  Future<void> _export() async {
    final path =
        await DailyReportService.exportToUserPath(day, entries);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path == null
          ? 'خروجی لغو شد'
          : 'فایل گزارش ذخیره شد:\n$path'),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: ShamsiDateField(
                label: 'روز گزارش',
                initial: day,
                onChanged: (d) {
                  if (d != null) day = d;
                },
              ),
            ),
            FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.query_stats, size: 18),
              label: const Text('نمایش'),
            ),
            OutlinedButton.icon(
              onPressed: entries.isEmpty ? null : _export,
              icon: const Icon(Icons.save_alt, size: 18),
              label: const Text('خروجی فایل (مسیر دلخواه)'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'همه تغییرات روز شامل پذیرش، تغییر کارتابل، تحویل، وصول، تخفیف، ابطال و حذف (بند ۱۷).',
          style: TextStyle(
              fontSize: 11.5, color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
                  ? const Center(
                      child: Text('برای این روز رخدادی ثبت نشده — «نمایش» را بزنید'))
                  : ListView(
                      children: [
                        for (final e in entries)
                          ListTile(
                            dense: true,
                            leading: SizedBox(
                              width: 46,
                              child: Text(e.time,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.blueGrey)),
                            ),
                            title: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(e.category,
                                  style: const TextStyle(fontSize: 11)),
                            ),
                            subtitle: Text(e.text,
                                style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}
