/// پوسته اصلی — بازطراحی کامل (قاعده ۱۱)
/// نوار کنار هوشمند: باز شدن خودکار با hover و جمع شدن با خروج موس (ویندوز)؛
/// کشویی با دکمه (اندروید). منوی آبشاری بخش‌های هر ماژول در نوار بالا.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';
import '../assistant/assistant_page.dart';
import '../board/board.dart';
import '../calendar/calendar_page.dart';
import '../customers/customers.dart';
import '../dbmanager/db_manager_page.dart';
import '../invoices/invoices.dart';
import '../intake/intake.dart';
import '../reminders/reminders.dart';
import '../settings/settings.dart';
import '../support/support.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final List<String> sections; // منوی آبشاری بالای ماژول
  const _NavItem(this.icon, this.label, {this.sections = const []});
}

class MainShell extends StatefulWidget {
  final AppSession session;
  const MainShell({super.key, required this.session});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  bool railPinned = false; // حالت موبایل: باز/بسته با دکمه
  bool hoverOpen = false;

  static const _items = <_NavItem>[
    _NavItem(Icons.dashboard, 'خانه',
        sections: ['خلاصه امروز', 'قابل وصول', 'ایمیل‌های در صف']),
    _NavItem(Icons.add_box, 'پذیرش',
        sections: ['فرم رسید سپردن', 'چک‌لیست لوازم', 'امضای مشتری']),
    _NavItem(Icons.view_kanban, 'کارتابل',
        sections: ['همه مراحل', 'آماده تحویل', 'انتظار قطعه']),
    _NavItem(Icons.people, 'مشتریان', sections: ['لیست', 'تاریخچه', 'برچسب‌ها']),
    _NavItem(Icons.receipt_long, 'فاکتورها',
        sections: ['همه فاکتورها', 'تسویه‌شده', 'بدهکار']),
    _NavItem(Icons.calendar_month, 'تقویم',
        sections: ['ماه جاری', 'تعطیلات رسمی', 'خروجی Google Calendar']),
    _NavItem(Icons.alarm, 'یادآوری‌ها',
        sections: ['پنجره یادآوری', 'ثبت‌شده‌ها']),
    _NavItem(Icons.auto_awesome, 'دستیار',
        sections: ['کارهای روتین', 'گزارش‌های فوری']),
    _NavItem(Icons.settings_backup_restore, 'دیتابیس',
        sections: ['بک‌آپ دستی', 'بک‌آپ اتوماتیک', 'پوشه', 'منطقه خطر']),
    _NavItem(Icons.settings, 'تنظیمات',
        sections: ['فروشگاه', 'ایمیل', 'یادآوری']),
    _NavItem(Icons.support_agent, 'پشتیبانی',
        sections: ['اطلاعات سازنده', 'لایسنس']),
  ];

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 760;
    final item = _items[index];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${AppInfo.appName} — ${item.label}'),
          centerTitle: false,
          actions: [
            // منوی آبشاری بخش‌های ماژول — قاعده ۱۱
            if (item.sections.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'بخش‌های ${item.label}',
                itemBuilder: (_) => [
                  for (final s in item.sections)
                    PopupMenuItem(value: s, child: Text(s)),
                ],
                onSelected: _onSection,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('بخش‌ها', style: TextStyle(fontSize: 12.5)),
                      Icon(Icons.expand_more, size: 17),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  'نصب ${toPersianDigits('${widget.session.license.installCount}')} از ${toPersianDigits('${AppInfo.maxInstalls}')}',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ),
            ),
          ],
          leading: isNarrow
              ? IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => setState(() => railPinned = !railPinned),
                )
              : null,
        ),
        body: Row(
          children: [
            if (!isNarrow) _smartRail(),
            const VerticalDivider(width: 1),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(index),
                child: _page(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSection(String s) {
    // بخش‌ها راهنمای دسترسی سریع هستند؛ در فازهای بعد به فیلترهای صفحه تبدیل می‌شوند
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$s — از داخل صفحه ${_items[index].label} استفاده کنید'),
      duration: const Duration(seconds: 2),
    ));
  }

  /// نوار کنار هوشمند — قاعده ۱۱: hover باز می‌شود، خروج موس جمع می‌کند
  Widget _smartRail() {
    const collapsedWidth = 62.0;
    const expandedWidth = 216.0;
    final open = hoverOpen || railPinned;

    return MouseRegion(
      onEnter: (_) => setState(() => hoverOpen = true),
      onExit: (_) => setState(() {
        hoverOpen = false;
        railPinned = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: open ? expandedWidth : collapsedWidth,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            left: BorderSide(color: Colors.grey.shade300, width: 0.6),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (var i = 0; i < _items.length; i++) _railItem(i, open),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railItem(int i, bool open) {
    final item = _items[i];
    final active = index == i;
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Colors.blueGrey.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() => index = i),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(item.icon, size: 21, color: color),
                if (open) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: active ? FontWeight.bold : FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        return _HomePage(session: widget.session, onGo: (n) => setState(() => index = n));
      case 1:
        return const IntakePage();
      case 2:
        return const BoardPage();
      case 3:
        return const CustomersPage();
      case 4:
        return const InvoicesPage();
      case 5:
        return const CalendarPage();
      case 6:
        return const RemindersPage();
      case 7:
        return const AssistantPage();
      case 8:
        return const DbManagerPage();
      case 9:
        return const SettingsPage();
      case 10:
        return const SupportPage();
      default:
        return const SizedBox();
    }
  }
}

/// صفحه خانه با کوئری‌های تجمیعی — بهینه برای سیستم ضعیف (قاعده ۱۱)
class _HomePage extends StatefulWidget {
  final AppSession session;
  final void Function(int) onGo;
  const _HomePage({required this.session, required this.onGo});

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  int openTickets = 0;
  int readyTickets = 0;
  int deliveredMonth = 0;
  int receivable = 0;
  bool pendingEmails = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    final itemSums = await TicketItemRepo.sumsForAllTickets();
    final paidSums = await PaymentRepo.paidSumForAll();
    var receivableSum = 0;
    for (final t in tickets) {
      if (t.status == 'delivered') continue;
      final itemsSum = itemSums[t.id] ?? 0;
      final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
      receivableSum += total - (paidSums[t.id] ?? 0);
    }
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final delivered = tickets
        .where((t) =>
            t.status == 'delivered' && t.updatedAt.startsWith(monthPrefix))
        .length;
    final pending = await EmailQueueRepo.hasPending();
    if (!mounted) return;
    setState(() {
      openTickets = tickets.where((t) => t.status != 'delivered').length;
      readyTickets = tickets.where((t) => t.status == 'ready').length;
      deliveredMonth = delivered;
      receivable = receivableSum;
      pendingEmails = pending;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(18),
      child: ListView(
        children: [
          Text('سلام! وضعیت امروز فروشگاه',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi('سفارش‌های باز', openTickets, Icons.work, Colors.indigo),
              _kpi('آماده تحویل', readyTickets, Icons.done_all, Colors.green),
              _kpi('تحویل این ماه', deliveredMonth, Icons.local_shipping, Colors.blue),
              _kpi('قابل وصول از مشتریان', receivable, Icons.payments,
                  Colors.deepOrange, money: true),
            ],
          ),
          if (pendingEmails)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: Colors.orange.shade50,
                child: const ListTile(
                  leading: Icon(Icons.hourglass_top, color: Colors.orange),
                  title: Text(
                      'ایمیل‌هایی در صف ارسال است — با وصل شدن اینترنت به‌صورت خودکار ارسال می‌شوند.'),
                ),
              ),
            ),
          const SizedBox(height: 16),
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
    return SizedBox(
      width: 215,
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color)),
          title: Text(label,
              style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey)),
          subtitle: Text(
            money ? moneyToman(value) : toPersianDigits('$value'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
