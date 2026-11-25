/// پیش‌بینی درآمد و وضعیت گارانتی — فاز ۲
/// پیش‌بینی صادقانه: میانگین متحرک ۳ ماه گذشته (برآورد است، نه قطعیت)
library;

import 'package:shamsi_date/shamsi_date.dart' as j;

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

  /// آمار گارانتی‌ها برای KPI داشبورد
  static Future<WarrantyStats> warrantyStats() async {
    final all = await WarrantyRepo.all();
    var active = 0, expiring = 0, expired = 0;
    for (final w in all) {
      switch (w.liveStatus()) {
        case 'active':
          active++;
          break;
        case 'expiring':
          expiring++;
          break;
        default:
          expired++;
      }
    }
    return WarrantyStats(active, expiring, expired);
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
