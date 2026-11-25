/// پوسته اصلی — ناوبری + صفحه خانه با خلاصه وضعیت
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/repos.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';
import '../board/board.dart';
import '../customers/customers.dart';
import '../invoices/invoices.dart';
import '../intake/intake.dart';
import '../reminders/reminders.dart';
import '../settings/settings.dart';
import '../support/support.dart';

class MainShell extends StatefulWidget {
  final AppSession session;
  const MainShell({super.key, required this.session});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <int, Widget Function()>{
      0: () => _HomePage(session: widget.session, onGo: (i) => setState(() => index = i)),
      1: () => const IntakePage(),
      2: () => const BoardPage(),
      3: () => const CustomersPage(),
      4: () => const InvoicesPage(),
      5: () => const RemindersPage(),
      6: () => const SettingsPage(),
      7: () => const SupportPage(),
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppInfo.appName),
          actions: [
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
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('خانه')),
                NavigationRailDestination(icon: Icon(Icons.add_box), label: Text('پذیرش')),
                NavigationRailDestination(icon: Icon(Icons.view_kanban), label: Text('کارتابل')),
                NavigationRailDestination(icon: Icon(Icons.people), label: Text('مشتریان')),
                NavigationRailDestination(icon: Icon(Icons.receipt_long), label: Text('فاکتورها')),
                NavigationRailDestination(icon: Icon(Icons.alarm), label: Text('یادآوری‌ها')),
                NavigationRailDestination(icon: Icon(Icons.settings), label: Text('تنظیمات')),
                NavigationRailDestination(icon: Icon(Icons.support_agent), label: Text('پشتیبانی')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: KeyedSubtree(key: ValueKey('$index-${tick()}'), child: pages[index]!())),
          ],
        ),
      ),
    );
  }

  static int tick() => DateTime.now().minute;
}

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
  int pendingEmails = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tickets = await TicketRepo.all();
    var receivableSum = 0;
    for (final t in tickets) {
      if (t.status == 'delivered') continue;
      final items = await TicketItemRepo.byTicket(t.id!);
      final itemsSum = items.fold<int>(0, (s, i) => s + i.price * i.qty);
      final total = itemsSum > 0 ? itemsSum : t.estimateAmount;
      final paid = await PaymentRepo.paidSum(t.id!);
      receivableSum += total - paid;
    }
    final now = DateTime.now();
    final monthTickets = tickets
        .where((t) =>
            t.status == 'delivered' &&
            t.updatedAt.startsWith('${now.year}-${now.month.toString().padLeft(2, '0')}'))
        .length;
    if (!mounted) return;
    setState(() {
      openTickets = tickets.where((t) => t.status != 'delivered').length;
      readyTickets = tickets.where((t) => t.status == 'ready').length;
      deliveredMonth = monthTickets;
      receivable = receivableSum;
    });
    pendingEmails = (await EmailQueueRepo.hasPending()) ? 1 : 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
              _kpi('قابل وصول از مشتریان', receivable, Icons.payments, Colors.deepOrange, money: true),
            ],
          ),
          if (pendingEmails > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: Colors.orange.shade50,
                child: const ListTile(
                  leading: Icon(Icons.hourglass_top, color: Colors.orange),
                  title: Text('ایمیل‌هایی در صف ارسال است — با وصل شدن اینترنت به‌صورت خودکار ارسال می‌شوند.'),
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
              icon: const Icon(Icons.alarm),
              label: const Text('یادآوری‌های امروز'),
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
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
          title: Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey)),
          subtitle: Text(
            money ? moneyToman(value) : toPersianDigits('$value'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
