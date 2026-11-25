/// گارانتی سطح سفارش — فاز ۲ (F-11)
/// هنگام تحویل، خودکار با ماه‌های تنظیم‌شده ساخته می‌شود؛ تمدید و پیگیری انقضا.
library;

import 'db/db.dart';
import 'repos.dart';

class WarrantyRecord {
  final int? id;
  final int ticketId;
  final DateTime startDate;
  final DateTime endDate;
  final int months;
  final String createdAt;

  const WarrantyRecord({
    this.id,
    required this.ticketId,
    required this.startDate,
    required this.endDate,
    required this.months,
    this.createdAt = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ticket_id': ticketId,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'months': months,
        'status': 'active',
        'created_at': createdAt.isEmpty
            ? DateTime.now().toIso8601String()
            : createdAt,
      };

  factory WarrantyRecord.fromMap(Map<String, Object?> m) => WarrantyRecord(
        id: m['id'] as int?,
        ticketId: m['ticket_id'] as int,
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: DateTime.parse(m['end_date'] as String),
        months: m['months'] as int,
        createdAt: (m['created_at'] ?? '') as String,
      );

  /// وضعیت پویا: فعال / نزدیک انقضا (۳۰ روز پایانی) / منقضی
  String liveStatus() {
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 'expired';
    if (endDate.difference(now).inDays <= 30) return 'expiring';
    return 'active';
  }
}

class WarrantyRepo {
  static Future<int> upsertForTicket(int ticketId, int months) async {
    final db = await Db.instance();
    final existing = await db.query('warranty_records',
        where: 'ticket_id = ?', whereArgs: [ticketId], limit: 1);
    final start = DateTime.now();
    final end = DateTime(start.year, start.month + months, start.day);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update(
        'warranty_records',
        {
          'start_date': start.toIso8601String(),
          'end_date': end.toIso8601String(),
          'months': months,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return db.insert(
      'warranty_records',
      WarrantyRecord(
        ticketId: ticketId,
        startDate: start,
        endDate: end,
        months: months,
      ).toMap(),
    );
  }

  static Future<WarrantyRecord?> forTicket(int ticketId) async {
    final db = await Db.instance();
    final rows = await db.query('warranty_records',
        where: 'ticket_id = ?', whereArgs: [ticketId], limit: 1);
    return rows.isEmpty ? null : WarrantyRecord.fromMap(rows.first);
  }

  static Future<List<WarrantyRecord>> all() async {
    final db = await Db.instance();
    final rows = await db.query('warranty_records', orderBy: 'end_date ASC');
    return rows.map(WarrantyRecord.fromMap).toList();
  }

  /// تمدید — افزودن ماه‌های جدید به انتهای گارانتی فعلی
  static Future<void> extend(int ticketId, int months) async {
    final w = await forTicket(ticketId);
    if (w == null) {
      await upsertForTicket(ticketId, months);
      return;
    }
    final base = w.endDate.isAfter(DateTime.now())
        ? w.endDate
        : DateTime.now();
    final newEnd =
        DateTime(base.year, base.month + months, base.day);
    final db = await Db.instance();
    await db.update(
      'warranty_records',
      {'end_date': newEnd.toIso8601String(), 'months': w.months + months},
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
    );
  }

  static Future<int> defaultMonths() async {
    final v = int.tryParse(await SettingsRepo.get('warranty_months')) ?? 6;
    return v.clamp(1, 60).toInt();
  }
}
