/// مدیریت کاربران و دسترسی تفکیکی — فاز ۲ (بند ۸ + بند ۲ جدید — قاعده ۱۲)
/// سربرگ‌ها: کاربران | عملکرد کاربران
/// - اکانت سازنده: فقط نمایش با نشان «سازنده» — بدون دکمه ویرایش/حذف
/// - کاربر عادی: ماتریس دسترسی (صفحات + عملیات‌ها + گذارهای وضعیت)
/// - گزارش عملکرد: تعداد کارها، پذیرش، تحویل، وصولی و سهم درصدی در بازه تاریخی
library;

import 'package:flutter/material.dart';

import '../../core/services/app_session.dart';
import '../../core/services/auth_service.dart';
import '../../core/repos.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/shamsi_date_field.dart';
import '../../shared/widgets/smart_data_table.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, Object?>> users = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // بند ۱ نسخه ۳ — اکانت سازنده در هیچ لیستی نمایش داده نمی‌شود (ورود او با نام کاربری خودش)
    final rows = (await UserRepo.list())
        .where((u) => (u['role'] ?? '') as String != kRoleCreator)
        .toList();
    if (!mounted) return;
    setState(() {
      users = rows;
      loading = false;
    });
  }

  String _roleFa(String role) {
    if (role == kRoleCreator) return 'سازنده';
    if (role == kRoleAdmin) return 'مدیر';
    return 'کاربر';
  }

  Future<void> _addUser() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _UserEditDialog(),
    );
    _load();
  }

  Future<void> _editUser(Map<String, Object?> u) async {
    final role = (u['role'] ?? '') as String;
    if (role == kRoleCreator) return; // محافظت سازنده
    await showDialog<void>(
      context: context,
      builder: (_) => _UserEditDialog(existing: u),
    );
    _load();
  }

  Future<void> _permsDialog(Map<String, Object?> u) async {
    final role = (u['role'] ?? '') as String;
    if (role != kRoleUser) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('مدیر و سازنده دسترسی کامل دارند — ماتریس فقط برای «کاربر» است'),
      ));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _PermsDialog(userId: u['id'] as int),
    );
    _load();
  }

  Future<void> _deleteUser(Map<String, Object?> u) async {
    final id = u['id'] as int;
    final role = (u['role'] ?? '') as String;
    if (role == kRoleCreator) return;
    final me = AppSession.I.currentUser;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کاربر'),
        content: Text(
            'کاربر «${u['username']}» حذف شود؟ دسترسی‌های ثبت‌شده او هم پاک می‌شود.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await UserRepo.delete(id, actor: me);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'کاربر حذف شد'),
      backgroundColor: err != null ? Colors.red : null,
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppSession.I.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('مدیریت کاربران',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _addUser,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('کاربر جدید'),
                  ),
                  const Spacer(),
                  if (me != null)
                    Chip(
                      avatar: Icon(
                        me.isCreator
                            ? Icons.engineering
                            : me.isAdmin
                                ? Icons.admin_panel_settings
                                : Icons.person,
                        size: 16,
                      ),
                      label: AppText(
                          '${me.bestName} (${me.roleLabelFa})',
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const TabBar(
                tabs: [
                  Tab(text: 'فهرست کاربران و دسترسی‌ها'),
                  Tab(text: 'گزارش عملکرد کاربران'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _usersTab(),
                    const _PerfTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _usersTab() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        for (final u in users) _userCard(u),
        const SizedBox(height: 8),
        AppText(
          'راهنما: مدیر و سازنده به همه بخش‌ها دسترسی دارند. برای کاربر عادی از دکمه «دسترسی‌ها» تعیین کنید '
          'دقیقاً کدام صفحات، عملیات‌ها و گذارهای وضعیت برای او مجاز باشد (بند ۸).',
          style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.outline,
              height: 1.7),
        ),
      ],
    );
  }

  Widget _userCard(Map<String, Object?> u) {
    final id = u['id'] as int;
    final role = (u['role'] ?? '') as String;
    final isCreator = role == kRoleCreator;
    final me = AppSession.I.currentUser;
    final isSelf = me?.id == id;
    final active = ((u['is_active'] ?? 1) as int) == 1;
    final displayName = (u['display_name'] ?? '') as String;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isCreator
                  ? Icons.engineering
                  : role == kRoleAdmin
                      ? Icons.admin_panel_settings
                      : Icons.person_outline,
              size: 26,
              color: isCreator
                  ? Colors.deepPurple
                  : role == kRoleAdmin
                      ? Colors.indigo
                      : Colors.blueGrey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppText(displayName.isEmpty ? u['username']! as String : displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(width: 8),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: AppText(_roleFa(role),
                            style: TextStyle(
                                fontSize: 10.5,
                                color: isCreator
                                    ? Colors.deepPurple
                                    : role == kRoleAdmin
                                        ? Colors.indigo
                                        : Colors.blueGrey)),
                        backgroundColor: isCreator
                            ? Colors.deepPurple.withValues(alpha: 0.08)
                            : null,
                      ),
                      if (!active) ...[
                        const SizedBox(width: 6),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: const Text('غیرفعال',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.red)),
                        ),
                      ],
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: const Text('شما',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.green)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    'نام کاربری: ${u['username']} — ایجاد: ${_faDate(u['created_at'] as String? ?? '')}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
            if (isCreator)
              Tooltip(
                message: 'اکانت سازنده بر پایه قاعده ۱۲ محافظت می‌شود — '
                    'قابل ویرایش و حذف نیست؛ رمز فقط به‌صورت هش ذخیره شده است',
                child: IconButton(
                  icon: const Icon(Icons.lock, color: Colors.deepPurple),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('اکانت سازنده قابل ویرایش و حذف نیست (قاعده ۱۲)'),
                    ));
                  },
                ),
              )
            else ...[
              IconButton(
                tooltip: 'دسترسی‌ها',
                icon: const Icon(Icons.key),
                onPressed: () => _permsDialog(u),
              ),
              IconButton(
                tooltip: 'ویرایش',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editUser(u),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteUser(u),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _faDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '-' : shamsiDate(d);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// گفت‌وگوی افزودن/ویرایش کاربر
// ─────────────────────────────────────────────────────────────────────────────
class _UserEditDialog extends StatefulWidget {
  final Map<String, Object?>? existing;
  const _UserEditDialog({this.existing});

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  late final TextEditingController userCtrl;
  late final TextEditingController nameCtrl;
  late final TextEditingController passCtrl;
  late String role;
  late bool active;

  bool get isEdit => widget.existing != null;
  bool get isCreator =>
      ((widget.existing?['role'] ?? '') as String) == kRoleCreator;
  bool get isSelf =>
      AppSession.I.currentUser?.id == (widget.existing?['id'] as int?);

  @override
  void initState() {
    super.initState();
    userCtrl = TextEditingController(text: (widget.existing?['username'] ?? '') as String);
    nameCtrl = TextEditingController(text: (widget.existing?['display_name'] ?? '') as String);
    passCtrl = TextEditingController();
    role = ((widget.existing?['role'] ?? kRoleUser) as String) == kRoleAdmin
        ? kRoleAdmin
        : kRoleUser;
    active = ((widget.existing?['is_active'] ?? 1) as int) == 1;
  }

  @override
  void dispose() {
    userCtrl.dispose();
    nameCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final me = AppSession.I.currentUser;
    String? err;
    if (isEdit) {
      final id = widget.existing!['id'] as int;
      // بند ۸: مدیر می‌تواند نام کاربری خودش را عوض کند
      if (userCtrl.text.trim() != (widget.existing!['username'] ?? '')) {
        err = await UserRepo.setUsername(
            id: id, username: userCtrl.text, actor: me);
      }
      err ??= await UserRepo.updateProfile(
        id: id,
        displayName: nameCtrl.text,
        role: role,
        isActive: active,
        actor: me,
      );
      if (passCtrl.text.isNotEmpty) {
        err ??= await UserRepo.setPassword(id: id, password: passCtrl.text);
      }
    } else {
      final (id, createErr) = await UserRepo.create(
        username: userCtrl.text,
        displayName: nameCtrl.text,
        role: role,
        password: passCtrl.text,
      );
      err = createErr;
    }
    if (!mounted) return;
    // UserRepo.create موفقیت را با '' برمی‌گرداند — فقط متن واقعی خطا نمایش داده شود
    if (err != null && err.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: Colors.red,
      ));
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(isEdit ? 'ویرایش کاربر' : 'کاربر جدید'),
        content: SizedBox(
          width: 380,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextField(
                controller: userCtrl,
                enabled: !isEdit || !isCreator,
                decoration: InputDecoration(
                  labelText: 'نام کاربری',
                  helperText: isEdit && isSelf
                      ? 'نام کاربری خودتان را می‌توانید عوض کنید (بند ۸)'
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'نام نمایشی'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: isEdit ? 'رمز جدید (خالی = بدون تغییر)' : 'رمز عبور',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'نقش'),
                items: const [
                  DropdownMenuItem(value: kRoleUser, child: Text('کاربر — دسترسی تفکیکی')),
                  DropdownMenuItem(value: kRoleAdmin, child: Text('مدیر — دسترسی کامل')),
                ],
                onChanged: (v) => setState(() => role = v ?? kRoleUser),
              ),
              if (isEdit) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('اکانت فعال باشد'),
                  value: active,
                  onChanged: isSelf
                      ? null // نمی‌توان خود را غیرفعال کرد
                      : (v) => setState(() => active = v),
                ),
              ],
              const SizedBox(height: 6),
              AppText(
                'پس از ثبت، از دکمه «دسترسی‌ها» ماتریس مجوزهای این کاربر را تعیین کنید.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          FilledButton(onPressed: _save, child: const Text('ذخیره')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// گفت‌وگوی ماتریس دسترسی — صفحات + عملیات‌ها + گذارهای وضعیت
// ─────────────────────────────────────────────────────────────────────────────
class _PermsDialog extends StatefulWidget {
  final int userId;
  const _PermsDialog({required this.userId});

  @override
  State<_PermsDialog> createState() => _PermsDialogState();
}

class _PermsDialogState extends State<_PermsDialog> {
  late Set<String> selected;

  @override
  void initState() {
    super.initState();
    selected = {};
    UserRepo.permsOf(widget.userId).then((keys) {
      if (!mounted) return;
      setState(() => selected = keys.toSet());
    });
  }

  Widget _section(String title, List<Map<String, String>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: AppText(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        for (final it in items)
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            value: selected.contains(it['key']),
            title: AppText(it['label']!, style: const TextStyle(fontSize: 12.5)),
            onChanged: (v) => setState(() {
              v == true
                  ? selected.add(it['key']!)
                  : selected.remove(it['key']);
            }),
          ),
      ],
    );
  }

  Future<void> _save() async {
    await UserRepo.setPerms(widget.userId, selected.toList());
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('دسترسی‌های کاربر'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              _section('دسترسی به صفحات', PermPages.all),
              _section('عملیات‌های مجاز', PermActions.all),
              _section('گذارهای وضعیت سفارش (رو به جلو)', PermTransitions.all),
              const SizedBox(height: 8),
              AppText(
                'برگشت وضعیت به مرحله قبل فقط توسط کاربری که آخرین تغییر را داده '
                'انجام می‌شود (با دسترسی «برگشت وضعیت» و ثبت دلیل) — بند ۸.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          FilledButton(onPressed: _save, child: const Text('ذخیره دسترسی‌ها')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// گزارش عملکرد کاربران — بند ۸ (مقایسه در بازه تاریخی)
// ─────────────────────────────────────────────────────────────────────────────
class _PerfRow {
  final Map<String, Object?> m;
  _PerfRow(this.m);
  String get name =>
      ((m['display_name'] ?? '') as String).isEmpty
          ? (m['username'] ?? '') as String
          : (m['display_name'] ?? '') as String;
  int get changes => (m['changes'] ?? 0) as int;
  int get accepted => (m['accepted'] ?? 0) as int;
  int get delivered => (m['delivered'] ?? 0) as int;
  int get intakes => (m['intakes'] ?? 0) as int;
  int get collected => (m['collected'] ?? 0) as int;
  double get share => ((m['share'] ?? 0) as num).toDouble();
}

class _PerfTab extends StatefulWidget {
  const _PerfTab();

  @override
  State<_PerfTab> createState() => _PerfTabState();
}

class _PerfTabState extends State<_PerfTab> {
  DateTime from = DateTime.now().subtract(const Duration(days: 30));
  DateTime to = DateTime.now().add(const Duration(days: 1));
  List<_PerfRow> rows = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => loading = true);
    final data = await TicketRepo.activityReport(
        from.toIso8601String(), to.toIso8601String());
    if (!mounted) return;
    setState(() {
      rows = data.map(_PerfRow.new).toList();
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: ShamsiDateField(
                label: 'از تاریخ',
                initial: from,
                onChanged: (d) {
                  if (d != null) from = d;
                },
              ),
            ),
            SizedBox(
              width: 150,
              child: ShamsiDateField(
                label: 'تا تاریخ',
                initial: to,
                onChanged: (d) {
                  if (d != null) to = d.add(const Duration(days: 1));
                },
              ),
            ),
            FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.query_stats, size: 18),
              label: const Text('نمایش گزارش'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : SmartDataTable<_PerfRow>(
                  rows: rows,
                  showSums: true,
                  searchIndex: (r) => r.name,
                  columns: [
                    SmartColumn<_PerfRow>(
                        label: 'کاربر', display: (r) => r.name, width: 140),
                    SmartColumn<_PerfRow>(
                        label: 'پذیرش ثبت‌شده',
                        display: (r) => toPersianDigits('${r.intakes}'),
                        numeric: (r) => r.intakes,
                        width: 110),
                    SmartColumn<_PerfRow>(
                        label: 'تحویل‌ها',
                        display: (r) => toPersianDigits('${r.delivered}'),
                        numeric: (r) => r.delivered,
                        width: 90),
                    SmartColumn<_PerfRow>(
                        label: 'تغییر وضعیت‌ها',
                        display: (r) => toPersianDigits('${r.changes}'),
                        numeric: (r) => r.changes,
                        width: 110),
                    SmartColumn<_PerfRow>(
                        label: 'وصولی (تومان)',
                        display: (r) => money(r.collected),
                        numeric: (r) => r.collected,
                        width: 140),
                    SmartColumn<_PerfRow>(
                        label: 'سهم از درآمد',
                        display: (r) =>
                            '${toPersianDigits(r.share.toStringAsFixed(1))}٪',
                        numeric: (r) => r.share,
                        width: 100),
                  ],
                ),
        ),
      ],
    );
  }
}
