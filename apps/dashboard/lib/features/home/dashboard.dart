/// داشبورد خانه — پوسته مدرن با نمودارها و پیش‌بینی (نسخه ۰.۳ + فاز ۲)
library;

import 'package:flutter/material.dart';

import '../../core/repos.dart';
import '../../core/models.dart';
import '../../core/services/app_session.dart';
import '../../core/services/forecast_service.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../shared/charts/modern_charts.dart';
import '../../shared/widgets/app_text.dart';

class DashboardPage extends StatefulWidget {
  final AppSession session;
  final void Function(int pageIndex) onGo;
  const DashboardPage({super.key, required this.session, required this.onGo});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loading = true;
  int openTickets = 0;
  int readyTickets = 0;
  int deliveredMonth = 0;
  int receivable = 0;
  int expiringWarranties = 0;
  List<ChartPoint> statusCounts = [];
  List<ChartPoint> receivableByStatus = [];
  List<ChartPoint> revenueLine = [];
  int dashedFrom = -1;

  // فاز ۲ — کارهای در دست کاربران (بند ۸)
  List<_UserWork> userWorks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final itemSums = await TicketItemRepo.sumsForAllTickets();
    final paidSums = await PaymentRepo.paidSumForAll();
    final forecast = await ForecastService.monthlyRevenue();
    final future = await ForecastService.forecast(months: 3);
    final wstats = await ForecastService.warrantyStats();

    // دونات: تعداد سفارش‌ها به تفکیک وضعیت
    final counts = <String, int>{};
    for (final t in tickets) {
      counts[statusLabel(t.status)] = (counts[statusLabel(t.status)] ?? 0) + 1;
    }
    // میله: قابل وصول به تفکیک وضعیت سفارش‌های باز
    final recv = <String, int>{};
    var receivableSum = 0;
    for (final t in tickets) {
      if (t.status == 'delivered') continue;
      final itemsSum = itemSums[t.id] ?? 0;
      final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
      final rem = total - (paidSums[t.id] ?? 0);
      if (rem > 0) {
        recv[statusLabel(t.status)] = (recv[statusLabel(t.status)] ?? 0) + rem;
        receivableSum += rem;
      }
    }
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // فاز ۲ — گروه‌بندی سفارش‌های باز بر اساس کاربر مسئول + زمان آخرین تغییر (بند ۸)
    final names = <int, String>{};
    for (final u in await UserRepo.list()) {
      final dn = (u['display_name'] ?? '') as String;
      names[u['id'] as int] =
          dn.isEmpty ? (u['username'] ?? '') as String : dn;
    }
    final works = <int, List<Ticket>>{};
    final lastChange = <int, String>{};
    for (final t in tickets) {
      if (t.status == TicketStatus.delivered) continue;
      final uid = t.assignedTo;
      if (uid == null) continue;
      works.putIfAbsent(uid, () => []).add(t);
      final log = await TicketRepo.statusLog(t.id!);
      if (log.isNotEmpty) {
        lastChange[uid] = log.last['created_at'] as String? ?? '';
      }
    }

    if (!mounted) return;
    setState(() {
      openTickets = tickets.where((t) => t.status != 'delivered').length;
      readyTickets = tickets.where((t) => t.status == 'ready').length;
      deliveredMonth = tickets
          .where((t) =>
              t.status == 'delivered' && t.updatedAt.startsWith(monthPrefix))
          .length;
      receivable = receivableSum;
      expiringWarranties = wstats.expiring + wstats.expired;
      statusCounts = [
        for (final e in counts.entries)
          if (e.value > 0) ChartPoint(e.key, e.value.toDouble()),
      ];
      receivableByStatus = [
        for (final e in recv.entries) ChartPoint(e.key, e.value.toDouble()),
      ];
      revenueLine = [
        ...forecast.map((f) => ChartPoint(f.label, f.value)),
        ...future.map((f) => ChartPoint(f.label, f.value)),
      ];
      dashedFrom = forecast.length;
      userWorks = [
        for (final e in works.entries)
          _UserWork(
            userName: names[e.key] ?? 'کاربر ${e.key}',
            userId: e.key,
            tickets: e.value,
            lastChange: lastChange[e.key] ?? '',
          ),
      ]..sort((a, b) => b.tickets.length.compareTo(a.tickets.length));
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              AppText('سلام! وضعیت امروز فروشگاه',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: AppNumText(shamsiDate(DateTime.now()),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: p.primary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── کارت‌های شاخص ──
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi('سفارش‌های باز', openTickets, Icons.work, p.chartColors[0]),
              _kpi('آماده تحویل', readyTickets, Icons.done_all, p.success),
              _kpi('تحویل این ماه', deliveredMonth, Icons.local_shipping,
                  p.chartColors[2]),
              _kpi('قابل وصول از مشتریان', receivable, Icons.payments,
                  p.warning, money: true),
              _kpi('گارانتی‌های در هشدار', expiringWarranties, Icons.verified_user,
                  p.danger),
            ],
          ),
          const SizedBox(height: 16),
          // ── فاز ۲ — کارهای در دست کاربران (بند ۸) ──
          if (userWorks.isNotEmpty) _userWorkCard(),
          const SizedBox(height: 12),
          if (cfg.showChartsOnDashboard) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _chartCard(
                  'وضعیت سفارش‌ها',
                  DonutChart(
                      points: statusCounts, centerLabel: 'سفارش‌ها', size: 200),
                  width: 380,
                ),
                _chartCard(
                  'روند درآمد و پیش‌بینی ۳ ماه آینده (برآورد میانگین متحرک)',
                  LineChart(
                    points: revenueLine,
                    dashedFutureFrom: dashedFrom,
                    height: 235,
                  ),
                  width: 560,
                ),
                _chartCard(
                  'قابل وصول به تفکیک وضعیت',
                  BarChart(bars: receivableByStatus, height: 235),
                  width: 560,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Wrap(spacing: 10, children: [
            FilledButton.icon(
              onPressed: () => widget.onGo(1),
              icon: const Icon(Icons.add_box),
              label: const Text('پذیرش دستگاه جدید'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onGo(7),
              icon: const Icon(Icons.calendar_month),
              label: const Text('تقویم سفارشات'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onGo(9),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('دستیار هوشمند'),
            ),
          ]),
        ],
      ),
    );
  }

  /// کارت «چه کاری در دست چه کاربری است» — بند ۸
  Widget _userWorkCard() {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handyman, size: 18, color: Colors.deepOrange),
                const SizedBox(width: 8),
                AppText('کارهای در دست کاربران — چه کاری در چه وضعیتی نزد چه کسی است',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: p.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            for (final w in userWorks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 15, color: Colors.blueGrey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: AppText(w.userName,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final t in w.tickets.take(8))
                            Tooltip(
                              message:
                                  '${t.code} — ${statusLabel(t.status)}',
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                label: AppText(
                                    '${toPersianDigits(t.code)} · ${statusLabel(t.status)}',
                                    style: const TextStyle(fontSize: 10.5)),
                              ),
                            ),
                          if (w.tickets.length > 8)
                            AppText(
                                '+ ${toPersianDigits('${w.tickets.length - 8}')} سفارش دیگر',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: p.textSecondary)),
                        ],
                      ),
                    ),
                    if (w.lastChange.isNotEmpty)
                      AppText(
                          'آخرین تغییر: ${_faTime(w.lastChange)}',
                          style: TextStyle(
                              fontSize: 10.5, color: p.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _faTime(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '-' : shamsiDateTime(d);
  }

  Widget _kpi(String label, num value, IconData icon, Color color,
      {bool money = false}) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    return SizedBox(
      width: 208,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius:
                      BorderRadius.circular(cfg.baseRadius * 0.65),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(label,
                        style: TextStyle(
                            fontSize: 11.5, color: p.textSecondary)),
                    const SizedBox(height: 4),
                    AppNumText(
                      money ? moneyToman(value) : toPersianDigits('$value'),
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: p.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartCard(String title, Widget child, {double width = 400}) {
    final cfg = AppThemeScope.of(context);
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: cfg.palette.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// فاز ۲ — خلاصه کار در دست یک کاربر (بند ۸)
class _UserWork {
  final String userName;
  final int userId;
  final List<Ticket> tickets;
  final String lastChange;
  const _UserWork({
    required this.userName,
    required this.userId,
    required this.tickets,
    required this.lastChange,
  });
}
