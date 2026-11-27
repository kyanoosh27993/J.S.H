/// سرویس آمار خانه — فاز ۴
/// خلاصه مالی، شاخص عملکرد کاربران و کوئری‌های فیلترشده با بازه تاریخی
/// کوئری‌ها مستقیماً روی Db.instance() اجرا می‌شوند تا به فایل‌های غیرمجاز دست نزنیم.
library;

import '../db/db.dart';

/// ── خلاصه مالی بازه ──
class FinancialSummary {
  /// جمع کل فاکتورهای قطعی غیر ابطالی (ناخالص)
  final int gross;

  /// جمع تخفیف‌ها
  final int discounts;

  /// خالص = ناخالص − تخفیف
  final int net;

  /// تعداد فاکتورهای لحاظ‌شده
  final int count;
  const FinancialSummary({
    required this.gross,
    required this.discounts,
    required this.net,
    required this.count,
  });
}

/// ── شاخص عملکرد یک کاربر (بند ۱۴/۹) ──
class EmployeeKpi {
  final int userId;
  final String name;
  final int created; // سفارش‌های ثبت‌شده توسط کاربر در بازه
  final int delivered; // از همان سفارش‌ها، تحویل‌شده‌ها در بازه
  final int cancelled; // ابطال‌شده‌ها (در حال حاضر وضعیت cancelled ندارد — معمولاً صفر)
  final double share; // سهم درصدی تحویل این کاربر از کل تحویل‌ها
  const EmployeeKpi({
    required this.userId,
    required this.name,
    required this.created,
    required this.delivered,
    required this.cancelled,
    required this.share,
  });
}

/// ── سرویس آمار صفحه خانه ──
class HomeStatsService {
  /// خلاصه مالی فاکتورهای قطعی غیر ابطالی صادره در بازه
  /// [from]/[to] میلادی؛ null یعنی همه زمان‌ها. مقایسه issued_at (ISO) به‌صورت رشته‌ای
  /// چون فرمت ISO8601 با ترتیب الفبایی هم‌ارز ترتیب زمانی است.
  static Future<FinancialSummary> financialSummary(
      DateTime? from, DateTime? to) async {
    final db = await Db.instance();
    final where = <String>["kind = 'final'", "status != 'cancelled'"];
    final args = <Object?>[];
    if (from != null) {
      where.add('issued_at >= ?');
      args.add(_dayStart(from).toIso8601String());
    }
    if (to != null) {
      // انتهای بازه — ابتدای روز بعد (شامل خود روز تا)
      where.add('issued_at < ?');
      args.add(_nextDay(to).toIso8601String());
    }
    final rows = await db.query('invoices',
        columns: ['total', 'discount'],
        where: where.join(' AND '),
        whereArgs: args);
    var gross = 0, disc = 0;
    for (final r in rows) {
      gross += (r['total'] ?? 0) as int;
      disc += (r['discount'] ?? 0) as int;
    }
    return FinancialSummary(
      gross: gross,
      discounts: disc,
      net: gross - disc,
      count: rows.length,
    );
  }

  /// شاخص عملکرد کاربران در بازه (بند ۱۴/۹)
  /// سفارش‌های ثبت‌شده (tickets.created_by)، تحویل‌شده‌ها (وضعیت delivered با
  /// updated_at در بازه) و ابطال‌ها؛ سهم درصدی تحویل هر کاربر از کل تحویل‌ها.
  static Future<List<EmployeeKpi>> employeeKpis(
      DateTime? from, DateTime? to) async {
    final db = await Db.instance();
    final users = await db.query('users',
        columns: ['id', 'username', 'display_name'], orderBy: 'id ASC');
    final whereT = <String>['1 = 1'];
    final args = <Object?>[];
    if (from != null) {
      whereT.add('intake_date >= ?');
      args.add(_dayStart(from).toIso8601String());
    }
    if (to != null) {
      whereT.add('intake_date < ?');
      args.add(_nextDay(to).toIso8601String());
    }
    final rows = await db.query('tickets',
        columns: ['created_by', 'status'], where: whereT.join(' AND '),
        whereArgs: args);
    final created = <int, int>{};
    final delivered = <int, int>{};
    final cancelled = <int, int>{};
    var totalDelivered = 0;
    for (final r in rows) {
      final uid = r['created_by'] as int?;
      if (uid == null) continue;
      created[uid] = (created[uid] ?? 0) + 1;
      final st = (r['status'] ?? '') as String;
      if (st == 'delivered') {
        delivered[uid] = (delivered[uid] ?? 0) + 1;
        totalDelivered++;
      } else if (st == 'cancelled') {
        cancelled[uid] = (cancelled[uid] ?? 0) + 1;
      }
    }
    final out = <EmployeeKpi>[];
    for (final u in users) {
      final id = u['id'] as int;
      final dn = (u['display_name'] ?? '') as String;
      final name = dn.isEmpty ? (u['username'] ?? '') as String : dn;
      final d = delivered[id] ?? 0;
      out.add(EmployeeKpi(
        userId: id,
        name: name,
        created: created[id] ?? 0,
        delivered: d,
        cancelled: cancelled[id] ?? 0,
        share: totalDelivered > 0 ? d * 100 / totalDelivered : 0,
      ));
    }
    // فقط کاربرانی که در بازه فعالیتی دارند
    return out.where((k) => k.created > 0 || k.delivered > 0).toList()
      ..sort((a, b) => b.created.compareTo(a.created));
  }

  /// ابتدای روز (ساعت ۰۰:۰۰)
  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// ابتدای روز بعد — برای شرط انتهای بازه (شامل روز «تا»)
  static DateTime _nextDay(DateTime d) {
    final s = _dayStart(d);
    return s.add(const Duration(days: 1));
  }
}
