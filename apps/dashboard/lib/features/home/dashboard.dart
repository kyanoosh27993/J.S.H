/// داشبورد خانه — پوسته مدرن با نمودارها و پیش‌بینی (نسخه ۰.۳ + فاز ۲)
library;

import 'package:flutter/material.dart';

import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/services/forecast_service.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
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
  bool pendingEmails = false;
  List<ChartPoint> statusCounts = [];
  List<ChartPoint> receivableByStatus = [];
  List<ChartPoint> revenueLine = [];
  int dashedFrom = -1;

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
    final pending = await EmailQueueRepo.hasPending();

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
      pendingEmails = pending;
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
          if (pendingEmails)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: p.warning.withValues(alpha: 0.12),
                child: ListTile(
                  leading: Icon(Icons.hourglass_top, color: p.warning),
                  title: AppText(
                      'ایمیل‌هایی در صف ارسال است — با وصل شدن اینترنت خودکار ارسال می‌شوند.',
                      style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
          const SizedBox(height: 16),
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
              onPressed: () => widget.onGo(5),
              icon: const Icon(Icons.calendar_month),
              label: const Text('تقویم سفارشات'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onGo(7),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('دستیار هوشمند'),
            ),
          ]),
        ],
      ),
    );
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
