/// مدیریت دیتابیس — قاعده ۹
/// بک‌آپ دستی/اتوماتیک + لیست/بازیابی/حذف + پوشه دلخواه + پاک‌سازی کامل (فقط سوپروایزر)
library;


import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/backup_service.dart';
import '../../core/services/supervisor_service.dart';
import '../../core/utils.dart';
import '../../shared/widgets/data_table_pro.dart';
import 'supervisor_gate.dart';

class DbManagerPage extends StatefulWidget {
  const DbManagerPage({super.key});

  @override
  State<DbManagerPage> createState() => _DbManagerPageState();
}

class _DbManagerPageState extends State<DbManagerPage> {
  String section = 'manual';
  List<BackupInfo> backups = [];
  bool busy = false;
  String message = '';
  final folderCtrl = TextEditingController();
  bool supervisor = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    folderCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => busy = true);
    final list = section == 'auto'
        ? await BackupService.listAuto()
        : await BackupService.listManual();
    final dir = await BackupService.backupDir();
    if (!mounted) return;
    setState(() {
      backups = list;
      folderCtrl.text = dir;
      supervisor = SupervisorService.active;
      busy = false;
    });
  }

  Future<void> _backupNow() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final path = await BackupService.manualBackup();
      await AuditRepo.log('manual_backup', path);
      setState(() => message = 'بک‌آپ ساخته شد: ${p.basename(path)}');
    } catch (e) {
      setState(() => message = 'خطا: $e');
    } finally {
      _load();
    }
  }

  Future<void> _restore(BackupInfo b) async {
    final ok1 = await _confirm(
      'بازیابی بک‌آپ',
      'همه اطلاعات فعلی با محتوای «${b.name}» جایگزین می‌شود.\n'
          'داده‌های بعد از این بک‌آپ از بین می‌روند. ادامه؟',
    );
    if (!ok1) return;
    final ok2 = await _confirm('تایید نهایی بازیابی', 'مطمئن هستید؟ این عملیات بازگشت‌ناپذیر است.');
    if (!ok2) return;
    setState(() => busy = true);
    try {
      await BackupService.restoreBackup(b.path);
      await AuditRepo.log('restore_backup', b.path);
      if (!mounted) return;
      setState(() => message = 'بازیابی انجام شد. برای اطمینان، برنامه را یک‌بار ببندید و باز کنید.');
    } catch (e) {
      if (mounted) setState(() => message = 'خطا: $e');
    } finally {
      _load();
    }
  }

  Future<void> _delete(BackupInfo b) async {
    final ok1 = await _confirm(
      'حذف بک‌آپ',
      'فایل «${b.name}» برای همیشه حذف می‌شود. ادامه؟',
    );
    if (!ok1) return;
    final ok2 = await _confirm('تایید نهایی حذف', 'مطمئن هستید؟ حذف بازگشت‌ناپذیر است.');
    if (!ok2) return;
    await BackupService.deleteBackup(b.path);
    await AuditRepo.log('delete_backup', b.path);
    _load();
  }

  Future<bool> _confirm(String title, String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg, style: const TextStyle(fontSize: 13, height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('بله، انجام بده'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _pickFolder() async {
    try {
      final path = await fs.getDirectoryPath();
      if (path != null) {
        await BackupService.setBackupDir(path);
        _load();
      }
    } catch (_) {
      // پلتفرم پشتیبانی نمی‌کند — کاربر مسیر را دستی وارد می‌کند
    }
  }

  Future<void> _saveFolder() async {
    if (folderCtrl.text.trim().isEmpty) return;
    await BackupService.setBackupDir(folderCtrl.text.trim());
    await AuditRepo.log('set_backup_dir', folderCtrl.text.trim());
    _load();
    if (mounted) {
      setState(() => message = 'پوشه بک‌آپ ذخیره شد.');
    }
  }

  Future<void> _wipeAll() async {
    final ok = await showSupervisorGate(context, 'پاک‌سازی کامل دیتابیس');
    if (!ok) return;
    final ok1 = await _confirm(
      'پاک‌سازی کامل برنامه',
      'تمام مشتریان، سفارش‌ها، پرداخت‌ها، فاکتورها و تنظیمات برای همیشه حذف می‌شوند '
          'و برنامه به حالت خام برمی‌گردد.\nاین عملیات فقط با اکانت سوپروایزر انجام می‌شود.',
    );
    if (!ok1) return;
    final ok2 = await _confirm(
      'هشدار نهایی',
      'این آخرین تایید است. همه اطلاعات از بین می‌رود و بازگشتی نیست!',
    );
    if (!ok2) return;
    try {
      await BackupService.autoBackup(); // بک‌آپ اضطراری قبل از پاک‌سازی
      await BackupService.wipeAllData();
      await AuditRepo.log('wipe_database', 'پاک‌سازی کامل توسط سوپروایزر');
      if (!mounted) {
        return;
      }
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('انجام شد'),
          content: const Text('دیتابیس پاک شد و برنامه خام است.\nیک بک‌آپ اضطراری هم قبل از پاک‌سازی ذخیره شد.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('خب'))],
        ),
      );
      _load();
    } catch (e) {
      if (mounted) setState(() => message = 'خطا: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // منوی آبشاری بخش‌های ماژول — قاعده ۱۱
            Row(
              children: [
                Text('مدیریت دیتابیس', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 14),
                PopupMenuButton<String>(
                  initialValue: section,
                  tooltip: 'بخش‌های این ماژول',
                  onSelected: (v) {
                    setState(() => section = v);
                    _load();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'manual', child: Text('بک‌آپ دستی')),
                    PopupMenuItem(value: 'auto', child: Text('بک‌آپ اتوماتیک')),
                    PopupMenuItem(value: 'folder', child: Text('پوشه بک‌آپ')),
                    PopupMenuItem(value: 'danger', child: Text('منطقه خطر')),
                  ],
                  child: Chip(
                    label: Text(_sectionLabel(section),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    avatar: const Icon(Icons.expand_more, size: 16),
                  ),
                ),
                const Spacer(),
                if (section != 'folder' && section != 'danger')
                  FilledButton.icon(
                    onPressed: busy ? null : _backupNow,
                    icon: const Icon(Icons.backup, size: 18),
                    label: const Text('بک‌آپ جدید'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (message.isNotEmpty)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(message, style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  String _sectionLabel(String s) {
    switch (s) {
      case 'auto':
        return 'بک‌آپ اتوماتیک';
      case 'folder':
        return 'پوشه بک‌آپ';
      case 'danger':
        return 'منطقه خطر';
      default:
        return 'بک‌آپ دستی';
    }
  }

  Widget _body() {
    switch (section) {
      case 'folder':
        return _folderSection();
      case 'danger':
        return _dangerSection();
      default:
        return _listSection();
    }
  }

  Widget _listSection() {
    return ListView(
      children: [
        if (section == 'auto')
          Card(
            color: Colors.orange.shade50,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'بک‌آپ‌های اتوماتیک هنگام خروج برنامه به‌صورت بی‌صدا گرفته می‌شوند و '
                'بعد از ۳۰ روز به‌طور خودکار حذف می‌شوند تا فضای سیستم پر نشود. '
                'هر وقت خواستید می‌توانید بازیابی یا حذف کنید.',
                style: TextStyle(fontSize: 12.5, height: 1.7),
              ),
            ),
          ),
        if (backups.isEmpty && !busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('بک‌آپی در این بخش نیست.'),
          )
        else
          DataTablePro<BackupInfo>(
            rows: backups,
                            tableId: 'backups',
            showSums: false,
            columns: [
              ProColumn<BackupInfo>(
                label: 'نام فایل',
                display: (b) => b.name,
                width: 300,
              ),
              ProColumn<BackupInfo>(
                label: 'تاریخ',
                display: (b) => shamsiDateTime(b.createdAt),
                width: 160,
                numeric: (b) => b.createdAt.millisecondsSinceEpoch,
              ),
              ProColumn<BackupInfo>(
                label: 'حجم',
                display: (b) => '${toPersianDigits('${(b.sizeBytes / 1024).round()}')} کیلوبایت',
                width: 110,
                numeric: (b) => b.sizeBytes,
              ),
            ],
            rowAction: (b) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'بازیابی',
                  icon: const Icon(Icons.restore, size: 19),
                  onPressed: () => _restore(b),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: Icon(Icons.delete, size: 19, color: Colors.red.shade400),
                  onPressed: () => _delete(b),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _folderSection() {
    return ListView(
      children: [
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'پوشه پیش‌فرض بک‌آپ را خودتان مشخص کنید. '
              'توصیه مهم: این پوشه را در درایوی غیر از درایو ویندوز (مثلاً D:) قرار دهید '
              'تا اگر ویندوز خراب شد یا دوباره نصب شد، بک‌آپ‌های شما پاک نشوند.',
              style: TextStyle(fontSize: 12.5, height: 1.8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: folderCtrl,
                decoration: const InputDecoration(
                  labelText: 'مسیر پوشه بک‌آپ',
                  hintText: 'مثال: D:/JSH_Backups',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('انتخاب پوشه'),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _saveFolder, child: const Text('ذخیره')),
          ],
        ),
      ],
    );
  }

  Widget _dangerSection() {
    return ListView(
      children: [
        Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    const Text('منطقه خطر',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'پاک‌سازی کامل دیتابیس: همه مشتریان، سفارش‌ها، پرداخت‌ها، فاکتورها، '
                  'یادآوری‌ها و تنظیمات برای همیشه حذف می‌شوند و برنامه به حالت خام برمی‌گردد.\n'
                  'این عملیات فقط با اکانت سوپروایزر انجام می‌شود تا حتی مدیران هم نتوانند '
                  'اطلاعات فروشگاه را پاک کنند.\n'
                  'قبل از پاک‌سازی، یک بک‌آپ اضطراری به‌صورت خودکار گرفته می‌شود.',
                  style: TextStyle(fontSize: 12.5, height: 1.8),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: _wipeAll,
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('پاک‌سازی کامل دیتابیس (فقط سوپروایزر)'),
                    ),
                    if (supervisor)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          backgroundColor: Colors.green.shade100,
                          label: const Text('حالت سوپروایزر فعال',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('گزارش رویدادهای امنیتی (آخرین ۵۰ مورد)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                FutureBuilder<List<Map<String, Object?>>>(
                  future: AuditRepo.recent(limit: 50),
                  builder: (_, snap) {
                    final rows = snap.data ?? [];
                    if (rows.isEmpty) {
                      return const Text('رویدادی ثبت نشده است',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey));
                    }
                    return Column(
                      children: [
                        for (final r in rows)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.security, size: 15),
                            title: Text((r['action'] ?? '') as String,
                                style: const TextStyle(fontSize: 12)),
                            subtitle: Text(
                                '${(r['detail'] ?? '') as String}\n${(r['created_at'] ?? '') as String}',
                                style: const TextStyle(fontSize: 10.5)),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
