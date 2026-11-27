/// داشبورد خانه — پوسته مدرن با نمودارها و پیش‌بینی (نسخه ۰.۳ + فاز ۲ + فاز ۴)
/// فاز ۴: فیلتر بازه تاریخی شمسی، خلاصه مالی، شاخص عملکرد کاربران (بند ۱۴/۹)
/// و دیالوگ هشدار گارانتی (بند ۱۱) + تعامل دونات.
library;

import 'package:flutter/material.dart';

import '../../core/repos.dart';
import '../../core/models.dart';
import '../../core/services/app_session.dart';
import '../../core/services/auth_service.dart' show kRoleCreator;
import '../../core/services/forecast_service.dart';
import '../../core/services/home_stats_service.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../features/tickets/ticket_detail.dart';
import '../../shared/charts/modern_charts.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/shamsi_date_field.dart';

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

  // فاز ۴ — فیلتر بازه تاریخی (خالی = همه زمان‌ها)
  final TextEditingController fromCtrl = TextEditingController();
  final TextEditingController toCtrl = TextEditingController();
  DateTime? fromDate;
  DateTime? toDate;

  // فاز ۴ — خلاصه مالی و شاخص عملکرد کاربران
  FinancialSummary? fin;
  List<EmployeeKpi> employeeKpis = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    fromCtrl.dispose();
    toCtrl.dispose();
    super.dispose();
  }

  /// سفارش در بازه انتخابی است؟ (شامل روز «تا»)
  bool _inRange(DateTime d) {
    if (fromDate != null) {
      final f = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      if (d.isBefore(f)) return false;
    }
    if (toDate != null) {
      final t =
          DateTime(toDate!.year, toDate!.month, toDate!.day)
              .add(const Duration(days: 1));
      if (!d.isBefore(t)) return false;
    }
    return true;
  }

  Future<void> _load() async {
    // یک ردیف خراب نباید کل صفحه را خالی کند (بند ۲۰ نسخه ۳)
    try {
      await _loadData();
    } catch (e) {
      debugPrint('dashboard _load error: $e');
    }
  }

  Future<void> _loadData() async {
    final allTickets = await TicketRepo.all();
    // فاز ۴ — همه آمار فقط برای سفارش‌های پذیرش‌شده در بازه
    final tickets =
        allTickets.where((t) => _inRange(t.intakeDate)).toList();
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

    // فاز ۴ — خلاصه مالی بازه (فاکتورهای قطعی غیر ابطالی)
    final finSum = await HomeStatsService.financialSummary(fromDate, toDate);
    // فاز ۴ — شاخص عملکرد کاربران در بازه (بند ۱۴/۹)
    final kpis = await HomeStatsService.employeeKpis(fromDate, toDate);

    // فاز ۲ — گروه‌بندی سفارش‌های باز بر اساس کاربر مسئول + زمان آخرین تغییر (بند ۸)
    final names = <int, String>{};
    for (final u in await UserRepo.list()) {
      // بند ۱ نسخه ۳ — سازنده با نام کاربری نمایش داده نشود
      if ((u['role'] ?? '') as String == kRoleCreator) continue;
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
      fin = finSum;
      employeeKpis = kpis;
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
          _dateFilterCard(),
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
              // بند ۱۱ — کارت هشدار گارانتی تپ‌پذیر است
              _kpi('گارانتی‌های در هشدار', expiringWarranties, Icons.verified_user,
                  p.danger, onTap: _showWarrantyDialog),
            ],
          ),
          const SizedBox(height: 16),
          _financialCard(),
          const SizedBox(height: 12),
          // فاز ۲ — کارهای در دست کاربران (بند ۸)
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
                    points: statusCounts,
                    centerLabel: 'سفارش‌ها',
                    size: 200,
                    onSegmentTap: (label) => _showSegmentDialog(label),
                    onCenterTap: () => _showSegmentDialog(null),
                  ),
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
          // فاز ۴ — شاخص عملکرد کاربران (بند ۱۴/۹) — فقط برای مجوزدارها
          if (_canSeeKpi()) _employeeKpiCard(),
          const SizedBox(height: 12),
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

  /// فاز ۴ — نمایش بخش KPI فقط برای مدیر/سازنده یا دارنده دسترسی page.kpi
  bool _canSeeKpi() {
    final me = AppSession.I.currentUser;
    return me == null || me.isAdmin || me.isCreator
        || me.perms.contains('page.kpi');
  }

  /// فاز ۴ — کارت فیلتر بازه تاریخی شمسی («از تاریخ» / «تا تاریخ»)
  Widget _dateFilterCard() {
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
                const Icon(Icons.date_range, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                AppText('فیلتر بازه تاریخی (بر اساس تاریخ پذیرش)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: p.textSecondary)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: ShamsiDateField(
                    controller: fromCtrl,
                    label: 'از تاریخ',
                    onChanged: (d) {
                      setState(() {
                        fromDate = d;
                      });
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: ShamsiDateField(
                    controller: toCtrl,
                    label: 'تا تاریخ',
                    onChanged: (d) {
                      setState(() {
                        toDate = d;
                      });
                      _load();
                    },
                  ),
                ),
                if (fromDate != null || toDate != null)
                  OutlinedButton.icon(
                    onPressed: _clearFilter,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('حذف فیلتر'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// پاک‌سازی فیلتر بازه و بارگذاری مجدد همه زمان‌ها
  void _clearFilter() {
    setState(() {
      fromDate = null;
      toDate = null;
      fromCtrl.clear();
      toCtrl.clear();
    });
    _load();
  }

  /// فاز ۴ — بخش «خلاصه مالی» فاکتورهای قطعی غیر ابطالی بازه
  Widget _financialCard() {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final f = fin;
    if (f == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                AppText('خلاصه مالی (فاکتورهای قطعی غیر ابطالی در بازه)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: p.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _kpi('جمع کل فروش (ناخالص)', f.gross, Icons.storefront,
                    p.chartColors[0], money: true),
                _kpi('جمع تخفیف‌ها', f.discounts, Icons.percent, p.warning,
                    money: true),
                _kpi('فروش خالص', f.net, Icons.account_balance_wallet,
                    p.success, money: true),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: RepaintBoundary(
                child: BarChart(
                  bars: [
                    ChartPoint('ناخالص', f.gross.toDouble()),
                    ChartPoint('تخفیف', f.discounts.toDouble()),
                    ChartPoint('خالص', f.net.toDouble()),
                  ],
                  height: 220,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// فاز ۴ — بخش شاخص عملکرد کاربران (بند ۱۴/۹)
  Widget _employeeKpiCard() {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    if (employeeKpis.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.leaderboard, size: 18, color: Colors.teal),
                const SizedBox(width: 8),
                AppText('شاخص عملکرد کاربران در بازه (بند ۱۴/۹)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: p.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            for (final k in employeeKpis) _employeeRow(k),
          ],
        ),
      ),
    );
  }

  /// یک ردیف KPI کاربر — نام، ثبت‌شده، تحویل‌شده، ابطال، سهم درصدی + نوار افقی
  Widget _employeeRow(EmployeeKpi k) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.person, size: 15, color: Colors.blueGrey),
          const SizedBox(width: 6),
          SizedBox(
            width: 140,
            child: AppText(k.name,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold)),
          ),
          AppNumText(
            'ثبت: ${toPersianDigits('${k.created}')} · تحویل: ${toPersianDigits('${k.delivered}')}'
            ' · ابطال: ${toPersianDigits('${k.cancelled}')}',
            style: TextStyle(fontSize: 11.5, color: p.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نوار افقی سهم تحویل
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (k.share / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: p.border.withValues(alpha: 0.4),
                    color: p.chartColors[2],
                  ),
                ),
                const SizedBox(height: 2),
                AppNumText(
                  'سهم تحویل: ${toPersianDigits(k.share.toStringAsFixed(1))}٪',
                  style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// فاز ۴ — دیالوگ هشدار گارانتی (بند ۱۱): اقلام در آستانه انقضا یا منقضی
  Future<void> _showWarrantyDialog() async {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final alerts = await ForecastService.warrantyAlertDetails();
    final relevant = alerts.where((a) => a.expired || a.expiring).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText('گارانتی‌های در هشدار',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: p.textPrimary)),
        content: SizedBox(
          width: 460,
          child: relevant.isEmpty
              ? const AppText('موردی در وضعیت هشدار یا انقضا وجود ندارد')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: relevant.length,
                  itemBuilder: (_, i) {
                    final a = relevant[i];
                    final danger = a.expired;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              TicketDetailPage(ticketId: a.ticketId),
                        ));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              danger ? Icons.error_outline : Icons.schedule,
                              size: 17,
                              color: danger ? p.danger : p.warning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                      '${toPersianDigits(a.ticketCode)} — ${a.itemName}',
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold)),
                                  AppText(
                                      'پایان: ${shamsiDate(a.endDate)}'
                                      ' · ${danger
                                          ? 'منقضی — ${toPersianDigits('${-a.daysLeft}')} روز پیش'
                                          : '${toPersianDigits('${a.daysLeft}')} روز باقیمانده'}',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: p.textSecondary)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_left, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  /// فاز ۴ — دیالوگ جزئیات تپ روی دونات (قطاع یا مرکز)
  void _showSegmentDialog(String? label) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    if (label == null) {
      // تپ روی مرکز — جمع کل
      final total = donutTotal(statusCounts).round();
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: AppText('سفارش‌ها',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: p.textPrimary)),
          content: AppNumText(
              'جمع کل سفارش‌های بازه: ${toPersianDigits('$total')}',
              style: TextStyle(color: p.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('بستن'),
            ),
          ],
        ),
      );
      return;
    }
    final pt = statusCounts.firstWhere(
      (e) => e.label == label,
      orElse: () => ChartPoint(label, 0),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(label,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: p.textPrimary)),
        content: AppNumText('تعداد: ${toPersianDigits('${pt.value.round()}')}',
            style: TextStyle(color: p.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
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
      {bool money = false, VoidCallback? onTap}) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final card = SizedBox(
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
    // فاز ۴ — کارت‌های قابل تپ (مثل هشدار گارانتی — بند ۱۱)
    if (onTap != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(cfg.baseRadius),
        onTap: onTap,
        child: card,
      );
    }
    return card;
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
              SizedBox(width: double.infinity, child: RepaintBoundary(child: child)),
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
