/// صفحه گزارش فعالیت‌ها — فاز ۹ (بند ۱۸ فایل ۲)
/// فهرست یکپارچه زمانی حسابرسی (audit_log) + تاریخچه وضعیت سفارش‌ها
/// (ticket_status_log): «چه زمانی — چه کسی — چه به چه» با فیلتر نوع عملکرد
/// (همه/ورود/سوپروایزر/فاکتور/گارانتی/واگذاری/کارتابل) و بازه تاریخ شمسی؛
/// همه زمان‌ها شمسی؛ نمایش ۲۰۰ ردیف آخر با دکمه «بیشتر».
library;

import 'package:flutter/material.dart';

import '../../core/db/db.dart';
import '../../core/services/supervisor_service.dart' show AuditRepo;
import '../../core/repos.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/shamsi_date_field.dart';

/// یک ردیف یکپارچه فعالیت — از audit_log یا ticket_status_log
class _ActivityRow {
  final DateTime at;
  final int? userId;
  final String who; // نام کاربر (در صورت امکان)
  final String category; // ورود/سوپروایزر/فاکتور/گارانتی/واگذاری/کارتابل/سایر
  final String what; // خلاصه عمل
  final String detail; // جزئیات کامل ثبت‌شده

  const _ActivityRow({
    required this.at,
    this.userId,
    required this.who,
    required this.category,
    required this.what,
    required this.detail,
  });
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  /// همه ردیف‌ها — مرتب نزولی بر زمان
  List<_ActivityRow> allRows = [];
  bool loading = true;

  // فیلترها — بند ۱۸ فایل ۲
  String categoryFilter = 'همه';
  DateTime? fromDate;
  DateTime? toDate;

  /// صفحه‌بندی — ۲۰۰ ردیف آخر با دکمه «بیشتر»
  int limit = 200;
  static const int pageSize = 200;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// دسته‌بندی هر اکشن حسابرسی — بند ۱۸ فایل ۲
  static String categoryOf(String action) {
    // ورود و خروج
    if (action == 'login' || action == 'logout' ||
        action == 'login_fail' || action == 'login_lockout') {
      return 'ورود';
    }
    // سوپروایزر و مدیریت کاربران/سیستم
    if (action.startsWith('user_') ||
        action == 'supervisor_fail' ||
        action == 'activation_success' ||
        action == 'manual_backup' ||
        action == 'restore_backup' ||
        action == 'delete_backup' ||
        action == 'set_backup_dir' ||
        action == 'wipe_database') {
      return 'سوپروایزر';
    }
    // فاکتور و صندوق
    if (action.startsWith('invoice_') || action == 'settle') {
      return 'فاکتور';
    }
    // گارانتی (بند ۲۵)
    if (action.startsWith('warranty_')) {
      return 'گارانتی';
    }
    // واگذاری سفارش
    if (action == 'ticket_assign') {
      return 'واگذاری';
    }
    if (action == 'status_change') {
      return 'کارتابل';
    }
    return 'سایر';
  }

  /// استخراج شناسه کاربر از متن لاگ‌های قدیمی (… — کاربر #N)
  static int? _userIdFromDetail(String detail) {
    final m = RegExp(r'کاربر #(\d+)').firstMatch(detail);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Future<void> _load() async {
    final rows = <_ActivityRow>[];

    // ۱) حسابرسی سراسری — audit_log (شناسه کاربر از متن لاگ استخراج می‌شود)
    final audits = await AuditRepo.recent(limit: 100000);
    final userNameCache = <int, String>{};
    for (final a in audits) {
      final action = (a['action'] ?? '') as String;
      final detail = ((a['detail'] ?? '') as String).trim();
      final at = DateTime.tryParse((a['created_at'] ?? '') as String);
      if (at == null) continue;
      final uid = _userIdFromDetail(detail);
      String? who;
      if (uid != null) {
        who = userNameCache.putIfAbsent(uid, () => '');
        if (who.isEmpty) {
          who = await UserRepo.displayNameOf(uid);
          userNameCache[uid] = who;
        }
      }
      rows.add(_ActivityRow(
        at: at,
        userId: uid,
        who: (who == null || who.isEmpty) ? '—' : who,
        category: categoryOf(action),
        what: actionFaOf(action),
        detail: detail,
      ));
    }

    // ۲) تاریخچه وضعیت سفارش‌ها — ticket_status_log (شامل تحویل و واگذاری)
    final logs = await _statusLogs();
    final ticketCodes = <int, String>{};
    for (final t in await TicketRepo.all()) {
      if (t.id != null) ticketCodes[t.id!] = t.code;
    }
    for (final l in logs) {
      final at = DateTime.tryParse((l['created_at'] ?? '') as String);
      if (at == null) continue;
      final ticketId = (l['ticket_id'] ?? 0) as int;
      final from = ((l['from_status'] ?? '') as String).trim();
      final to = ((l['to_status'] ?? '') as String).isNotEmpty
          ? ((l['to_status'] ?? '') as String)
          : ((l['status'] ?? '') as String);
      final reason = ((l['reason'] ?? '') as String).trim();
      final note = ((l['note'] ?? '') as String).trim();
      final uid = l['user_id'] as int?;
      final assignedTo = l['assigned_to'] as int?;
      final hasFrom = from.isNotEmpty && from != to;
      final code = ticketCodes[ticketId] ?? '#$ticketId';
      // واگذاری بدون تغییر وضعیت — ردیفی که از/به یکسان‌اند و assigned_to دارد
      final isAssign = !hasFrom && assignedTo != null && assignedTo != 0;
      final what = hasFrom
          ? '${statusLabel(from)} ← ${statusLabel(to)}'
          : statusLabel(to);
      String who = 'سیستم';
      if (uid != null && uid != 0) {
        who = userNameCache.putIfAbsent(uid, () => '');
        if (who.isEmpty) {
          who = await UserRepo.displayNameOf(uid);
          userNameCache[uid] = who;
        }
        if (who.isEmpty) who = 'کاربر #${toPersianDigits('$uid')}';
      }
      rows.add(_ActivityRow(
        at: at,
        userId: uid,
        who: who,
        category: isAssign ? 'واگذاری' : 'کارتابل',
        what: 'سفارش ${toPersianDigits(code)}: $what',
        detail: [
          if (assignedTo != null && assignedTo != 0 && isAssign)
            'واگذار به کاربر #${toPersianDigits('$assignedTo')}',
          if (reason.isNotEmpty) 'دلیل: $reason',
          if (note.isNotEmpty) note,
        ].join(' — '),
      ));
    }

    rows.sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      allRows = rows;
      loading = false;
    });
  }

  /// خواندن کل ticket_status_log برای فهرست یکپارچه
  Future<List<Map<String, Object?>>> _statusLogs() async {
    final db = await Db.instance();
    return db.query('ticket_status_log', orderBy: 'created_at DESC');
  }

  /// برچسب فارسی هر اکشن حسابرسی — «چه به چه»
  static String actionFaOf(String action) {
    const map = {
      'login': 'ورود به برنامه',
      'login_fail': 'تلاش ناموفق ورود',
      'login_lockout': 'قفل‌شدن ورود',
      'logout': 'خروج از حساب',
      'invoice_create': 'صدور سند',
      'invoice_cancel': 'ابطال سند',
      'invoice_restore': 'بازگردانی سند از ابطال',
      'invoice_delete': 'حذف کامل سند',
      'invoice_discount': 'اعمال تخفیف',
      'invoice_cost_edit': 'ویرایش مبالغ سند',
      'settle': 'وصول/تسویه',
      'warranty_adjust': 'تنظیم گارانتی',
      'ticket_assign': 'واگذاری سفارش',
      'status_change': 'تغییر وضعیت سفارش',
      'user_create': 'ایجاد کاربر',
      'user_update': 'ویرایش کاربر',
      'user_rename': 'تغییر نام کاربری',
      'user_password': 'تغییر رمز',
      'user_delete': 'حذف کاربر',
      'user_perms': 'تغییر دسترسی‌ها',
      'user_seed': 'بذر کاربر پیش‌فرض',
      'supervisor_fail': 'رمز سوپروایزر ناموفق',
      'activation_success': 'فعال‌سازی برنامه',
      'manual_backup': 'بک‌آپ دستی',
      'restore_backup': 'بازیابی بک‌آپ',
      'delete_backup': 'حذف بک‌آپ',
      'set_backup_dir': 'تغییر پوشه بک‌آپ',
      'wipe_database': 'پاک‌سازی منطقه خطر',
      'attach_add': 'افزودن پیوست',
      'attach_delete': 'حذف پیوست',
    };
    return map[action] ?? action;
  }

  List<_ActivityRow> get _filtered {
    return allRows.where((r) {
      if (categoryFilter != 'همه' && r.category != categoryFilter) {
        return false;
      }
      if (fromDate != null && r.at.isBefore(fromDate!)) return false;
      if (toDate != null &&
          r.at.isAfter(toDate!.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final shown = _filtered.take(limit).toList();
    final categories = [
      'همه',
      'ورود',
      'سوپروایزر',
      'فاکتور',
      'گارانتی',
      'واگذاری',
      'کارتابل',
      'سایر',
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppText('گزارش فعالیت‌ها (بند ۱۸)',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() => loading = true);
                    _load();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('به‌روزرسانی'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: categoryFilter,
                    decoration: const InputDecoration(
                      labelText: 'نوع عملکرد',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) => setState(() {
                      categoryFilter = v ?? 'همه';
                      limit = pageSize;
                    }),
                  ),
                ),
                SizedBox(
                  width: 165,
                  child: ShamsiDateField(
                    label: 'از تاریخ',
                    initial: fromDate,
                    onChanged: (d) => setState(() {
                      fromDate = d;
                      limit = pageSize;
                    }),
                  ),
                ),
                SizedBox(
                  width: 165,
                  child: ShamsiDateField(
                    label: 'تا تاریخ',
                    initial: toDate,
                    onChanged: (d) => setState(() {
                      toDate = d;
                      limit = pageSize;
                    }),
                  ),
                ),
                Text(
                    '${toPersianDigits('${_filtered.length}')} رخداد',
                    style: TextStyle(
                        fontSize: 12, color: p.textSecondary)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? Center(
                          child: AppText(
                          'رخدادی در این بازه/دسته ثبت نشده است',
                          style: TextStyle(
                              color: p.textSecondary, fontSize: 13),
                        ))
                      : ListView.builder(
                          itemCount: shown.length + (shown.length < _filtered.length ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= shown.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: FilledButton.tonal(
                                    onPressed: () =>
                                        setState(() => limit += pageSize),
                                    child: const Text('بیشتر'),
                                  ),
                                ),
                              );
                            }
                            return _activityTile(shown[i], p);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityTile(_ActivityRow r, p) {
    final color = switch (r.category) {
      'ورود' => Colors.blue,
      'سوپروایزر' => Colors.deepPurple,
      'فاکتور' => Colors.teal,
      'گارانتی' => Colors.green,
      'واگذاری' => Colors.orange,
      'کارتابل' => Colors.indigo,
      _ => Colors.grey,
    };
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(shamsiDateTime(r.at),
                style: const TextStyle(
                    fontSize: 10.5, color: Colors.blueGrey)),
            Chip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              backgroundColor: color.withValues(alpha: 0.14),
              label: Text(r.category,
                  style: TextStyle(
                      fontSize: 10, color: color)),
            ),
          ],
        ),
      ),
      title: Text(
        '${r.what} — ${r.who}',
        style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600),
      ),
      subtitle: r.detail.isEmpty
          ? null
          : Text(r.detail,
              style: const TextStyle(fontSize: 11, height: 1.6)),
    );
  }
}
