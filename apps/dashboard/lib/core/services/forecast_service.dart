/// پیش‌بینی درآمد و وضعیت گارانتی — فاز ۲
/// پیش‌بینی صادقانه: میانگین متحرک ۳ ماه گذشته (برآورد است، نه قطعیت)
library;

import 'package:shamsi_date/shamsi_date.dart' as j;

import '../models.dart' show TicketItem;
import '../repos.dart';
import '../warranty.dart';

class ForecastPoint {
  final String label; // برچسب ماه شمسی
  final double value;
  final bool isForecast;
  const ForecastPoint(this.label, this.value, {this.isForecast = false});
}

class WarrantyStats {
  final int active;
  final int expiring;
  final int expired;
  const WarrantyStats(this.active, this.expiring, this.expired);
}

/// یک مورد هشدار گارانتی — برای دیالوگ داشبورد (بند ۱۱)
class WarrantyAlert {
  final int ticketId;
  final String ticketCode;
  final String itemName; // برای گارانتی سطح سفارش «گارانتی سفارش»
  final DateTime endDate;
  final int daysLeft; // منفی یعنی منقضی
  final bool fromRecord; // از جدول warranty_records یا از اقلام سفارش
  const WarrantyAlert({
    required this.ticketId,
    required this.ticketCode,
    required this.itemName,
    required this.endDate,
    required this.daysLeft,
    required this.fromRecord,
  });

  bool get expired => daysLeft < 0;
  bool get expiring => !expired && daysLeft <= 30;
}

class ForecastService {
  /// درآمد تحویل‌شده هر ماه به‌جای درآمد، جمع اقلام تحویل ماه
  static Future<List<ForecastPoint>> monthlyRevenue({int backMonths = 6}) async {
    final tickets = await TicketRepo.all();
    final itemSums = await TicketItemRepo.sumsForAllTickets();
    final now = DateTime.now();
    final out = <ForecastPoint>[];
    for (var i = backMonths - 1; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      var sum = 0;
      for (final t in tickets) {
        if (t.status != 'delivered') continue;
        final at = DateTime.tryParse(t.updatedAt) ?? t.dueDate;
        if (at.year == m.year && at.month == m.month) {
          sum += itemSums[t.id] ?? t.estimateAmount;
        }
      }
      out.add(ForecastPoint(_monthLabel(m), sum.toDouble()));
    }
    return out;
  }

  /// پیش‌بینی n ماه بعد = میانگین ۳ ماه کامل گذشته (برآورد)
  static Future<List<ForecastPoint>> forecast({int months = 3}) async {
    final past = await monthlyRevenue(backMonths: 3);
    final avg =
        past.fold<double>(0, (s, e) => s + e.value) / (past.isEmpty ? 1 : past.length);
    final now = DateTime.now();
    return [
      for (var i = 1; i <= months; i++)
        ForecastPoint(
          _monthLabel(DateTime(now.year, now.month + i)),
          avg,
          isForecast: true,
        ),
    ];
  }

  /// آمار گارانتی‌ها برای KPI داشبورد — ترکیب دو منبع (فاز ۴، رفع همیشه-صفر):
  /// ۱) رکوردهای warranty_records (ساخته‌شده هنگام تحویل)
  /// ۲) گارانتی سطح قلم: ticket_items.warranty_months سفارش‌های تحویل‌شده
  ///    که تاریخ پایانشان (updated_at + ماه‌ها) در بازه انقضا/هشدار است.
  static Future<WarrantyStats> warrantyStats() async {
    final alerts = await warrantyAlertDetails();
    var active = 0;
    var expiring = 0;
    var expired = 0;
    for (final a in alerts) {
      if (a.expired) {
        expired++;
      } else if (a.expiring) {
        expiring++;
      } else {
        active++;
      }
    }
    return WarrantyStats(active, expiring, expired);
  }

  /// فهرست کامل هشدارهای گارانتی — برای دیالوگ KPI گارانتی (بند ۱۱)
  /// هر دو منبع: رکورد سطح سفارش + اقلام با warranty_months سفارش‌های تحویل‌شده.
  static Future<List<WarrantyAlert>> warrantyAlertDetails() async {
    final now = DateTime.now();
    final out = <WarrantyAlert>[];
    // منبع ۱ — رکوردهای warranty_records
    for (final w in await WarrantyRepo.all()) {
      final t = await TicketRepo.byId(w.ticketId);
      out.add(WarrantyAlert(
        ticketId: w.ticketId,
        ticketCode: t?.code ?? '—',
        itemName: 'گارانتی سفارش (${w.months} ماهه)',
        endDate: w.endDate,
        daysLeft: w.endDate.difference(now).inDays,
        fromRecord: true,
      ));
    }
    // منبع ۲ — اقلام گارانتی‌دار سفارش‌های تحویل‌شده (مشابه warranty_page)
    final tickets = await TicketRepo.all(status: 'delivered');
    for (final t in tickets) {
      final items = await TicketItemRepo.byTicket(t.id!);
      final start = DateTime.tryParse(t.updatedAt) ?? now;
      for (final it in items) {
        if (it.warrantyMonths <= 0) continue;
        final end =
            DateTime(start.year, start.month + it.warrantyMonths, start.day);
        out.add(WarrantyAlert(
          ticketId: t.id!,
          ticketCode: t.code,
          itemName: it.description,
          endDate: end,
          daysLeft: end.difference(now).inDays,
          fromRecord: false,
        ));
      }
    }
    out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return out;
  }

  /// برچسب فارسی ماه (شمسی) — کبیسه و ماه‌ها با shamsi_date درست است
  static String _monthLabel(DateTime gregorian) {
    const names = [
      'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
      'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
    ];
    final jl = j.Jalali.fromDateTime(gregorian);
    return names[(jl.month - 1).clamp(0, 11)];
  }
}
