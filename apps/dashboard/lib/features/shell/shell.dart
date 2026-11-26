/// پوسته اصلی مدرن — نسخه ۰.۳
/// سایدبار شناور شیشه‌ای با انیمیشن hover و باز/جمع شدن خودکار (ویندوز)،
/// منوی کشویی در موبایل، منوی آبشاری بخش‌ها، سوییچر سریع تم و ترنزیشن صفحات.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/theme_config.dart';
import '../../core/services/activation_service.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/hover_tile.dart';
import '../assistant/assistant_page.dart';
import '../board/board.dart';
import '../calendar/calendar_page.dart';
import '../customers/customers.dart';
import '../dbmanager/db_manager_page.dart';
import '../home/dashboard.dart';
import '../invoices/invoices.dart';
import '../intake/intake.dart';
import '../reminders/reminders.dart';
import '../settings/settings.dart';
import '../settings/theme_settings.dart';
import '../support/support.dart';
import '../warranty/warranty_page.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final List<String> sections;
  const _NavItem(this.icon, this.label, {this.sections = const []});
}

class MainShell extends StatefulWidget {
  final AppSession session;

  /// روزهای باقیمانده اعتبار کد فعال‌سازی — اگر بین ۱ تا ۷ باشد، هشدار هر ورود نمایش داده می‌شود (بند ۱۸)
  final int? expiryNoticeDays;
  const MainShell({super.key, required this.session, this.expiryNoticeDays});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  bool railPinned = false;
  bool hoverOpen = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showExpiryNoticeIfAny();
    });
  }

  void _showExpiryNoticeIfAny() {
    final d = widget.expiryNoticeDays;
    if (d == null || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: Icon(Icons.alarm_on_rounded,
              color: d <= 3 ? Colors.red : Colors.orange, size: 34),
          title: const Text('یادآوری اعتبار برنامه',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: Text(
            ActivationService.expiryWarningMessage(d),
            style: const TextStyle(fontSize: 13.5, height: 1.9),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('متوجه شدم'),
            ),
          ],
        ),
      ),
    );
  }

  static const _items = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, 'خانه',
        sections: ['خلاصه امروز', 'نمودارها', 'پیش‌بینی درآمد']),
    _NavItem(Icons.add_box_rounded, 'پذیرش',
        sections: ['فرم رسید سپردن', 'چک‌لیست لوازم', 'امضای مشتری']),
    _NavItem(Icons.view_kanban_rounded, 'کارتابل',
        sections: ['همه مراحل', 'آماده تحویل', 'انتظار قطعه']),
    _NavItem(Icons.people_alt_rounded, 'مشتریان',
        sections: ['لیست', 'تاریخچه', 'برچسب‌ها']),
    _NavItem(Icons.receipt_long_rounded, 'فاکتورها',
        sections: ['همه فاکتورها', 'تسویه‌شده', 'بدهکار']),
    _NavItem(Icons.calendar_month_rounded, 'تقویم',
        sections: ['ماه جاری', 'تعطیلات رسمی', 'خروجی Google Calendar']),
    _NavItem(Icons.alarm_rounded, 'یادآوری‌ها',
        sections: ['پنجره یادآوری', 'ثبت‌شده‌ها']),
    _NavItem(Icons.auto_awesome_rounded, 'دستیار',
        sections: ['کارهای روتین', 'گزارش‌های فوری']),
    _NavItem(Icons.verified_user_rounded, 'گارانتی',
        sections: ['فعال', 'نزدیک انقضا', 'منقضی']),
    _NavItem(Icons.settings_backup_restore_rounded, 'دیتابیس',
        sections: ['بک‌آپ دستی', 'بک‌آپ اتوماتیک', 'پوشه', 'منطقه خطر']),
    _NavItem(Icons.settings_rounded, 'تنظیمات',
        sections: ['فروشگاه', 'ایمیل', 'یادآوری', 'گارانتی']),
    _NavItem(Icons.palette_rounded, 'تم و ظاهر',
        sections: ['سه تم پیش‌فرض', 'فونت متن و اعداد', 'شخصی‌سازی ریز']),
    _NavItem(Icons.support_agent_rounded, 'پشتیبانی',
        sections: ['اطلاعات سازنده', 'لایسنس']),
  ];

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final isNarrow = MediaQuery.of(context).size.width < 760;
    final item = _items[index];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: AppText('${AppInfo.appName} — ${item.label}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          centerTitle: false,
          actions: [
            if (item.sections.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'بخش‌های ${item.label}',
                itemBuilder: (_) => [
                  for (final s in item.sections)
                    PopupMenuItem(value: s, child: AppText(s, style: const TextStyle(fontSize: 12.5))),
                ],
                onSelected: _onSection,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText('بخش‌ها', style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
                      Icon(Icons.expand_more, size: 17, color: p.textSecondary),
                    ],
                  ),
                ),
              ),
            // سوییچر سریع تم — سه پیش‌فرض
            PopupMenuButton<String>(
              tooltip: 'تغییر سریع تم',
              icon: Icon(Icons.palette_outlined, size: 20, color: p.textSecondary),
              onSelected: (v) {
                final c = ThemeConfig.notifier.value.copyWith(preset: v);
                ThemeConfig.save(c);
              },
              itemBuilder: (_) => [
                for (final preset in ThemePreset.values)
                  PopupMenuItem(
                    value: preset.key,
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 13,
                          color: preset == ThemePreset.dark
                              ? const Color(0xFF4F8CFF)
                              : preset == ThemePreset.light
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFFD4A437),
                        ),
                        const SizedBox(width: 8),
                        AppText(preset.labelFa, style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'شخصی‌سازی کامل ظاهر',
              icon: Icon(Icons.tune, size: 20, color: p.textSecondary),
              onPressed: () => setState(() => index = 11),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: AppNumText(
                  'نصب ${toPersianDigits('${widget.session.license.installCount}')} از ${toPersianDigits('${AppInfo.maxInstalls}')}',
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
              ),
            ),
          ],
          leading: isNarrow
              ? IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                )
              : null,
        ),
        drawer: isNarrow ? _mobileDrawer(cfg) : null,
        body: Row(
          children: [
            if (!isNarrow) _floatingRail(cfg),
            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: cfg.animations ? 220 : 0),
                switchInCurve: Curves.easeOut,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.015),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(index),
                  child: _page(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSection(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$s — از داخل صفحه ${_items[index].label} استفاده کنید'),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── سایدبار شناور — هاور باز، خروج موس جمع می‌کند (قاعده ۱۱ و طراحی مدرن) ──
  Widget _floatingRail(ThemeConfig cfg) {
    const collapsedWidth = 68.0;
    const expandedWidth = 218.0;
    final open = hoverOpen || railPinned;
    final p = cfg.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => hoverOpen = true),
      onExit: (_) => setState(() {
        hoverOpen = false;
        railPinned = false;
      }),
      child: AnimatedContainer(
        duration: Duration(milliseconds: cfg.animations ? 200 : 0),
        curve: Curves.easeOut,
        width: open ? expandedWidth : collapsedWidth,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: p.sidebarGradient,
          ),
          borderRadius: BorderRadius.circular(cfg.baseRadius * 1.2),
          border: Border.all(color: p.border, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                  alpha: p.brightness == Brightness.dark ? 0.35 : 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // برند
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        p.primary,
                        p.accent,
                      ]),
                      borderRadius:
                          BorderRadius.circular(cfg.baseRadius * 0.65),
                    ),
                    child: const Icon(Icons.build_circle, color: Colors.white, size: 22),
                  ),
                  if (open) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppText(AppInfo.appName,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: p.textPrimary)),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                children: [
                  for (var i = 0; i < _items.length; i++) _railItem(i, open, cfg),
                ],
              ),
            ),
            const Divider(height: 8),
            // سه تم پیش‌فرض پایین سایدبار
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  for (final preset in ThemePreset.values)
                    _themeDot(preset, cfg, open),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeDot(ThemePreset preset, ThemeConfig cfg, bool open) {
    final color = preset == ThemePreset.dark
        ? const Color(0xFF4F8CFF)
        : preset == ThemePreset.light
            ? const Color(0xFF2563EB)
            : const Color(0xFFD4A437);
    final active = cfg.preset == preset.key;
    return Tooltip(
      message: preset.labelFa,
      child: GestureDetector(
        onTap: () => ThemeConfig.save(
            ThemeConfig.notifier.value.copyWith(preset: preset.key)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 16,
          height: active ? 22 : 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: active ? cfg.palette.accent : Colors.transparent,
                width: 2),
          ),
          child: active
              ? const Icon(Icons.check, size: 11, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _railItem(int i, bool open, ThemeConfig cfg) {
    final item = _items[i];
    final active = index == i;
    final p = cfg.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: HoverTile(
        active: active,
        radius: cfg.baseRadius * 0.8,
        hoverColor: p.primary.withValues(alpha: 0.12),
        activeColor: p.primary.withValues(alpha: 0.18),
        animate: cfg.animations,
        onTap: () => setState(() => index = i),
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 8),
              // نشانگر فعال
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 3.5,
                height: active ? 26 : 0,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Icon(item.icon,
                  size: 21,
                  color: active ? p.primary : p.textSecondary),
              if (open) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: AppText(
                    item.label,
                    style: TextStyle(
                        fontSize: 13,
                        color: active ? p.primary : p.textPrimary,
                        fontWeight: active ? FontWeight.bold : FontWeight.w500),
                  ),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileDrawer(ThemeConfig cfg) {
    final p = cfg.palette;
    return Drawer(
      backgroundColor: p.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration:
                BoxDecoration(gradient: LinearGradient(colors: p.sidebarGradient)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.build_circle, color: p.primary, size: 34),
                const SizedBox(height: 8),
                AppText(AppInfo.appName,
                    style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          for (var i = 0; i < _items.length; i++)
            ListTile(
              leading: Icon(_items[i].icon,
                  color: index == i ? p.primary : p.textSecondary),
              title: AppText(_items[i].label,
                  style: TextStyle(
                      color: index == i ? p.primary : p.textPrimary,
                      fontWeight: index == i ? FontWeight.bold : FontWeight.w500)),
              onTap: () {
                setState(() => index = i);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        return DashboardPage(session: widget.session, onGo: (n) => setState(() => index = n));
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
        return const WarrantyPage();
      case 9:
        return const DbManagerPage();
      case 10:
        return const SettingsPage();
      case 11:
        return const ThemeSettingsPage();
      case 12:
        return SupportPage(session: widget.session);
      default:
        return const SizedBox();
    }
  }
}

