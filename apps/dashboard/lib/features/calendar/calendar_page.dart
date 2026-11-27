/// صفحه تقویم شمسی سفارشات — قاعده ۳
/// نمایش سفارش‌ها با رنگ وضعیت + تعطیلات رسمی + خروجی Google Calendar
/// + فاز ۹ (بند ۲۶): اسناد ابطال‌شده با نشان مجزا (قرمز/خاکستری) در روز
/// صدور، نشان «ابطال» در راهنمای رنگ‌ها و دیالوگ جزئیات (شماره، نوع، دلیل).
library;

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/calendar_export_service.dart';
import '../../core/utils.dart';
import '../../shared/data/holidays.dart';
import '../tickets/ticket_detail.dart';

/// رنگ هر وضعیت برای نمایش در تقویم
Color statusColor(String status) {
  switch (status) {
    case TicketStatus.intake:
      return Colors.blue;
    case TicketStatus.diagnosis:
      return const Color(0xFF8A54B5);
    case TicketStatus.waitingPart:
      return Colors.orange;
    case TicketStatus.repairing:
      return Colors.deepOrange;
    case TicketStatus.testing:
      return Colors.teal;
    case TicketStatus.ready:
      return Colors.green;
    case TicketStatus.delivered:
      return Colors.blueGrey;
    default:
      return Colors.grey;
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late j.Jalali view;
  Map<String, List<Ticket>> byDay = {};
  // فاز ۹ — بند ۲۶: اسناد ابطالی به تفکیک روز صدور (ردیف خام invoices)
  Map<String, List<Map<String, Object?>>> cancelledByDay = {};
  bool includeDelivered = true;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    view = j.Jalali.now();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final map = <String, List<Ticket>>{};
    for (final t in tickets) {
      if (!includeDelivered && t.status == TicketStatus.delivered) continue;
      final jd = j.Jalali.fromDateTime(t.dueDate);
      map.putIfAbsent('${jd.year}-${jd.month}-${jd.day}', () => []).add(t);
    }
    // فاز ۹ — بند ۲۶: ابطالی‌ها با کوئری ریپازیتوری (قابل تست) و نمایش
    // بر پایه روز صدور سند (issued_at)؛ دیالوگ، زمان ابطال را هم می‌گوید.
    final now = DateTime.now();
    final cancelled = <String, List<Map<String, Object?>>>{};
    final invs = await InvoiceRepo.cancelledInRange(
        DateTime(now.year - 6, 1, 1), DateTime(now.year + 6, 1, 1));
    for (final inv in invs) {
      final dt =
          DateTime.tryParse((inv['issued_at'] ?? '') as String);
      if (dt == null) continue;
      final jd = j.Jalali.fromDateTime(dt);
      cancelled
          .putIfAbsent('${jd.year}-${jd.month}-${jd.day}', () => [])
          .add(inv);
    }
    if (!mounted) return;
    setState(() {
      byDay = map;
      cancelledByDay = cancelled;
    });
  }

  Future<void> _export() async {
    setState(() => exporting = true);
    try {
      final path = await CalendarExportService.exportDeliveries();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('خروجی Google Calendar ساخته شد'),
          content: Text(
            'فایل رویدادها ساخته شد:\n$path\n\n'
            'برای افزودن به تقویم گوگل:\n'
            '۱) در Google Calendar: Settings → Import & export\n'
            '۲) فایل بالا را انتخاب و Import کنید.\n'
            'مواعده تحویل با یادآور اضافه می‌شوند.',
            style: const TextStyle(fontSize: 12.5, height: 1.7),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('خب')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekDay = j.Jalali(view.year, view.month, 1).weekDay;
    final len = j.Jalali(view.year, view.month, 1).monthLength;
    final today = j.Jalali.now();
    final cells = <int?>[
      for (var i = 1; i < firstWeekDay; i++) null,
      for (var d = 1; d <= len; d++) d,
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('تقویم سفارشات', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 10),
                Text('${monthName(view.month)} ${toPersianDigits('${view.year}')}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: 'ماه قبل',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => view = _shift(-1)),
                ),
                IconButton(
                  tooltip: 'ماه بعد',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => view = _shift(1)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    view = j.Jalali.now();
                    _load();
                  }),
                  child: const Text('امروز'),
                ),
                const SizedBox(width: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    value: includeDelivered,
                    onChanged: (v) {
                      includeDelivered = v ?? true;
                      _load();
                    },
                  ),
                  const Text('تحویل‌شده‌ها', style: TextStyle(fontSize: 12)),
                ]),
                FilledButton.tonalIcon(
                  onPressed: exporting ? null : _export,
                  icon: exporting
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download, size: 18),
                  label: const Text('خروجی Google Calendar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // راهنمای رنگ‌ها — + بند ۲۶: نشان ابطال‌شده‌ها
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in TicketStatus.order)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: statusColor(s).withValues(alpha: 0.15),
                    label: Text(statusLabel(s),
                        style: TextStyle(fontSize: 10.5, color: statusColor(s))),
                  ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.red.withValues(alpha: 0.12),
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                  avatar: Icon(Icons.block, size: 12, color: Colors.red),
                  label: Text('ابطال سند',
                      style: TextStyle(fontSize: 10.5, color: Colors.red)),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.grey.shade300,
                  side: BorderSide(color: Colors.grey.shade500),
                  avatar: Icon(Icons.block, size: 12, color: Colors.grey.shade600),
                  label: Text('پیش‌فاکتور ابطالی',
                      style: TextStyle(
                          fontSize: 10.5, color: Colors.grey.shade700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // سرستون روزهای هفته
            Row(
              children: [
                for (var w = 1; w <= 7; w++)
                  Expanded(
                    child: Center(
                      child: Text(weekDayName(w),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: w == 7 ? Colors.red : Colors.blueGrey,
                          )),
                    ),
                  ),
              ],
            ),
            // شبکه روزها
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.05,
                ),
                itemCount: cells.length,
                itemBuilder: (context, idx) {
                  final d = cells[idx];
                  if (d == null) return const SizedBox();
                  return _dayCell(d, today);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  j.Jalali _shift(int delta) {
    var y = view.year;
    var m = view.month + delta;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    return j.Jalali(y, m, 1);
  }

  Widget _dayCell(int d, j.Jalali today) {
    final date = j.Jalali(view.year, view.month, d);
    final holiday = holidayName(date);
    final friday = isFriday(date);
    final thursday = isThursday(date);
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final tickets = byDay['${date.year}-${date.month}-${date.day}'] ?? [];
    final cancelled = cancelledByDay['${date.year}-${date.month}-${date.day}'] ?? [];

    // بند ۱۶ — روزهای عادی سفید؛ تعطیلات رسمی/جمعه خاکستری خیلی کمرنگ
    final isHoliday = holiday != null || friday;
    return InkWell(
      onTap: () => _dayDialog(date, tickets, cancelled),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isHoliday
              ? Colors.grey.shade200
              : thursday
                  ? Colors.grey.shade100
                  : Colors.white,
          border: isToday
              ? Border.all(color: Colors.blue, width: 1.6)
              : Border.all(color: Colors.grey.shade300, width: 0.5),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Row(
                children: [
                  Text(toPersianDigits('$d'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isHoliday
                            ? Colors.grey.shade600
                            : Colors.black87,
                      )),
                  const Spacer(),
                  if (holiday != null)
                    Tooltip(
                      message: holiday,
                      child: Icon(Icons.celebration,
                          size: 11, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
            if (holiday != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(holiday,
                    style: TextStyle(
                        fontSize: 7.5, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: (tickets.length + cancelled.length)
                    .clamp(0, 4),
                itemBuilder: (_, i) {
                  // بند ۲۶ — نشان مجزا «ابطال»: فاکتور قطعی قرمز،
                  // پیش‌فاکتور خاکستری؛ کلیک → دیالوگ جزئیات سند ابطالی
                  if (i >= tickets.length) {
                    final c = cancelled[i - tickets.length];
                    final isFinal =
                        (c['kind'] ?? '') == InvoiceRepo.kindFinal;
                    final color = isFinal ? Colors.red : Colors.grey;
                    return InkWell(
                      onTap: () => _voidedDialog(c),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isFinal ? 0.14 : 0.35),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: color.withValues(alpha: 0.6),
                              width: 0.6),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'ابطال ${(c['number'] ?? '') as String}',
                            style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: color),
                          ),
                        ),
                      ),
                    );
                  }
                  if (tickets.length + cancelled.length > 3 && i == 3) {
                    return Text(
                        '+${toPersianDigits('${tickets.length + cancelled.length - 3}')} مورد دیگر',
                        style: const TextStyle(
                            fontSize: 8.5, color: Colors.blueGrey));
                  }
                  final t = tickets[i];
                  final color = statusColor(t.status);
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TicketDetailPage(ticketId: t.id!),
                      ));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: color.withValues(alpha: 0.5), width: 0.6),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${t.code} — ${statusLabel(t.status)}',
                          style: TextStyle(fontSize: 8.5, color: color),
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

  /// بند ۱۶ + بند ۲۶ — کلیک روی روز → لیست کامل کارهای آن روز + اسناد ابطالی
  void _dayDialog(j.Jalali date, List<Ticket> tickets,
      List<Map<String, Object?>> cancelled) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
              'کارهای روز ${toPersianDigits('${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}')}'),
          content: SizedBox(
            width: 380,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (tickets.isEmpty && cancelled.isEmpty)
                  const Text('کاری برای این روز ثبت نشده است'),
                for (final t in tickets)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.flag,
                        size: 16, color: statusColor(t.status)),
                    title: Text(
                        '${t.code} — ${statusLabel(t.status)}',
                        style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(
                        'موعد تحویل ${shamsiDate(t.dueDate)}',
                        style: const TextStyle(fontSize: 10.5)),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TicketDetailPage(ticketId: t.id!),
                      ));
                    },
                  ),
                for (final c in cancelled)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.block,
                        size: 16,
                        color: (c['kind'] ?? '') == InvoiceRepo.kindFinal
                            ? Colors.red
                            : Colors.grey.shade500),
                    title: Text(
                        'ابطال سند ${toPersianDigits((c['number'] ?? '') as String)}'
                        ' — ${(c['kind'] ?? '') == InvoiceRepo.kindFinal ? 'فاکتور قطعی' : 'پیش‌فاکتور'}',
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.red)),
                    subtitle: Text(
                        'دلیل: ${((c['cancel_reason'] ?? '') as String).isEmpty ? '—' : (c['cancel_reason'] ?? '') as String}',
                        style: const TextStyle(fontSize: 10.5)),
                  ),
              ],
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

  /// فاز ۹ — بند ۲۶: کلیک روی نشان ابطال یک روز → دیالوگ جزئیات سند
  /// (شماره، نوع، دلیل ابطال و زمان ابطال)
  void _voidedDialog(Map<String, Object?> inv) {
    final kind = (inv['kind'] ?? '') == InvoiceRepo.kindFinal;
    final cancelledAt = DateTime.tryParse((inv['cancelled_at'] ?? '') as String);
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: Icon(Icons.block,
              size: 30, color: kind ? Colors.red : Colors.grey),
          title: Text(
              'سند ابطال‌شده ${toPersianDigits((inv['number'] ?? '') as String)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نوع: ${kind ? 'فاکتور قطعی' : 'پیش‌فاکتور'}',
                  style: const TextStyle(fontSize: 13)),
              Text('جمع: ${moneyToman((inv['total'] ?? 0) as int)} تومان',
                  style: const TextStyle(fontSize: 13)),
              Text('تاریخ صدور: ${shamsiDate(DateTime.tryParse((inv['issued_at'] ?? '') as String) ?? DateTime.now())}',
                  style: const TextStyle(fontSize: 13)),
              Text(
                  'زمان ابطال: ${cancelledAt == null ? '—' : shamsiDateTime(cancelledAt)}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Text(
                  'دلیل ابطال: ${((inv['cancel_reason'] ?? '') as String).isEmpty ? '—' : (inv['cancel_reason'] ?? '') as String}',
                  style: const TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('خب')),
          ],
        ),
      ),
    );
  }
}
