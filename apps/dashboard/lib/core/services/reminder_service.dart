/// موتور یادآوری (F-05 + N-01) — فاصله یادآوری و ساعت آن را کاربر تعیین می‌کند.
/// یادآوری شامل: کارهای مانده تا تحویل، بیعانه، مبلغ افزوده نسبت به برآورد، مجموع قابل وصول.
library;

import 'dart:async';

import '../constants.dart';
import '../db/db.dart';
import '../models.dart';
import '../repos.dart';

class TodayTask {
  final Ticket ticket;
  final int deposit;
  final int addedAmount;
  final int totalEstimate;
  final int collectable;
  final int daysLeft;

  TodayTask({
    required this.ticket,
    required this.deposit,
    required this.addedAmount,
    required this.totalEstimate,
    required this.collectable,
    required this.daysLeft,
  });
}

class ReminderService {
  static Timer? _timer;

  /// نسخه همگام برای محاسبه از روی اقلام موجود در حافظه
  static int addedOf(Ticket t, List<TicketItem> items) {
    final sum = items.fold<int>(0, (s, i) => s + (i.price * i.qty));
    final added = sum - t.estimateAmount;
    return added > 0 ? added : 0;
  }

  /// محاسبه «مبلغ افزوده» نسبت به برآورد اولیه اعلامی به مشتری:
  /// جمع قطعات/خدمات ثبت‌شده − برآورد اولیه (اگر بیشتر باشد)
  static Future<int> addedAmount(Ticket t) async {
    final items = await TicketItemRepo.byTicket(t.id!);
    final itemsSum =
        items.fold<int>(0, (s, i) => s + (i.price * i.qty));
    final added = itemsSum - t.estimateAmount;
    return added > 0 ? added : 0;
  }

  static Future<TodayTask> buildTask(Ticket t) async {
    final due = DateTime.parse(
        '${t.dueDate.toIso8601String().substring(0, 10)}T${t.dueTime}:00');
    // حسابرسی (قاعده ۱۰): روزهای باقی‌مانده می‌تواند منفی باشد (موعد گذشته)
    final daysLeft = due.difference(DateTime.now()).inDays;
    final added = await addedAmount(t);
    final items = await TicketItemRepo.byTicket(t.id!);
    final itemsSum = items.fold<int>(0, (s, i) => s + (i.price * i.qty));
    final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
    final paid = await PaymentRepo.paidSum(t.id!);
    return TodayTask(
      ticket: t,
      deposit: t.depositAmount,
      addedAmount: added,
      totalEstimate: total,
      collectable: total - paid,
      daysLeft: daysLeft,
    );
  }

  /// تضمین وجود رکورد یادآوری برای سفارش: موعد − leadDays، در ساعت تنظیم کاربر
  static Future<void> ensureForTicket(Ticket t, int leadDays, int hour) async {
    if (t.id == null) return;
    final existing = await ReminderRepo.forTicket(t.id!);
    if (existing != null) return;
    final dueFull = DateTime(
      t.dueDate.year, t.dueDate.month, t.dueDate.day,
      _parseHour(t.dueTime), _parseMinute(t.dueTime),
    );
    final remindAt = dueFull.subtract(Duration(days: leadDays));
    final remindFull = DateTime(remindAt.year, remindAt.month, remindAt.day, hour, 0);
    await ReminderRepo.insert(Reminder(
      ticketId: t.id,
      type: 'delivery',
      remindAt: remindFull,
      message:
          'یادآوری تحویل سفارش ${t.code} — کارهای مانده، بیعانه و مبلغ قابل وصول را بررسی کنید.',
    ));
  }

  static int _parseHour(String hhmm) =>
      int.tryParse(hhmm.split(':').first) ?? 18;
  static int _parseMinute(String hhmm) {
    final p = hhmm.split(':');
    return p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
  }

  /// یادآوری‌های رسیده که هنوز نمایش داده نشده‌اند
  static Future<List<Reminder>> duePending() async {
    return ReminderRepo.pendingBefore(DateTime.now());
  }

  /// چرخه دوره‌ای: هر ۱۵ دقیقه بررسی یادآوری‌ها
  static void startPeriodicCheck(Future<void> Function(Reminder) onDue) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) async {
      try {
        final due = await duePending();
        for (final r in due) {
          await onDue(r);
          await ReminderRepo.markShown(r.id!);
        }
      } catch (_) {}
    });
  }

  static void stopPeriodicCheck() {
    _timer?.cancel();
    _timer = null;
  }

  /// تنظیمات یادآوری از تنظیمات فروشگاه (پیش‌فرض ۳ روز، ساعت ۹)
  static Future<(int, int)> loadPrefs() async {
    final lead =
        int.tryParse(await SettingsRepo.get('reminder_lead_days')) ??
            ReminderPrefs.defaultLeadDays;
    final hour =
        int.tryParse(await SettingsRepo.get('reminder_hour')) ??
            ReminderPrefs.defaultHour;
    return (
      // بند ۱ — عدد دلخواه ۱ تا ۳۰؛ خارج از بازه به پیش‌فرض می‌رسد
      ReminderPrefs.minLeadDays <= lead && lead <= ReminderPrefs.maxLeadDays
          ? lead
          : ReminderPrefs.defaultLeadDays,
      hour.clamp(0, 23).toInt(),
    );
  }

  /// حسابرسی (قاعده ۱۰): تغییر تنظیمات یادآوری توسط کاربر باید یادآوری‌های
  /// در انتظار سفارش‌های باز را هم با تنظیم جدید هم‌گام کند.
  static Future<int> recomputePendingReminders(int leadDays, int hour) async {
    final tickets = await TicketRepo.all();
    var changed = 0;
    for (final t in tickets) {
      if (t.status == 'delivered' || t.id == null) continue;
      final existing = await ReminderRepo.forTicket(t.id!);
      if (existing == null || existing.status != 'pending') continue;
      final dueFull = DateTime(
        t.dueDate.year, t.dueDate.month, t.dueDate.day,
        _parseHour(t.dueTime), _parseMinute(t.dueTime),
      );
      final remindAt = dueFull.subtract(Duration(days: leadDays));
      final newTime =
          DateTime(remindAt.year, remindAt.month, remindAt.day, hour, 0);
      if (!newTime.isAtSameMomentAs(existing.remindAt)) {
        final db = await Db.instance();
        await db.update('reminders', {'remind_at': newTime.toIso8601String()},
            where: 'id = ?', whereArgs: [existing.id]);
        changed++;
      }
    }
    return changed;
  }
}
