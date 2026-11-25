/// سرویس بک‌آپ — قاعده ۹
/// بک‌آپ دستی به پوشه دلخواه + بک‌آپ اتوماتیک هنگام خروج (بی‌صدا)
/// + حذف خودکار بک‌آپ‌های اتوماتیک بعد از ۳۰ روز + بازیابی و حذف با هشدار
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/db.dart';
import '../repos.dart';

enum BackupKind { manual, auto }

class BackupInfo {
  final String path;
  final BackupKind kind;
  final DateTime createdAt;
  final int sizeBytes;

  BackupInfo({
    required this.path,
    required this.kind,
    required this.createdAt,
    required this.sizeBytes,
  });

  String get name => p.basename(path);

  static BackupInfo fromFile(File f) {
    final name = p.basename(f.path);
    final kind = name.contains('_auto_') ? BackupKind.auto : BackupKind.manual;
    final stamp = RegExp(r'(\d{8})_(\d{6})').firstMatch(name);
    DateTime created = f.lastModifiedSync();
    if (stamp != null) {
      final s = stamp.group(1)! + stamp.group(2)!;
      final parsed = DateTime.tryParse(
          '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}T'
          '${s.substring(8, 10)}:${s.substring(10, 12)}:${s.substring(12)}');
      if (parsed != null) created = parsed;
    }
    return BackupInfo(
      path: f.path,
      kind: kind,
      createdAt: created,
      sizeBytes: f.lengthSync(),
    );
  }
}

class BackupService {
  /// پوشه بک‌آپ: انتخاب کاربر از تنظیمات؛ پیش‌فرض: اسناد/JSH_backups
  static Future<String> backupDir() async {
    final configured = await SettingsRepo.get('backup_dir');
    if (configured.trim().isNotEmpty) {
      final d = Directory(configured.trim());
      if (!await d.exists()) await d.create(recursive: true);
      return configured.trim();
    }
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'JSH_backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  static Future<void> setBackupDir(String path) async {
    await SettingsRepo.set('backup_dir', path.trim());
    await Directory(path.trim()).create(recursive: true);
  }

  static Future<String> _make(String tag) async {
    final dir = await backupDir();
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final target = p.join(dir, 'JSH_backup_${tag}_$stamp.db');
    final created = await Db.backupTo(target);
    // تازگی فایل برای مرتب‌سازی درست
    await File(created).setLastModified(now);
    return created;
  }

  /// بک‌آپ دستی با نام و پیام نتیجه
  static Future<String> manualBackup() => _make('manual');

  /// بک‌آپ اتوماتیک هنگام خروج — بی‌صدا؛ خطا نادیده گرفته می‌شود
  static Future<void> autoBackup() async {
    try {
      await _make('auto');
      await cleanupAutoBackups();
    } catch (_) {}
  }

  static Future<List<BackupInfo>> listAll() async {
    final dir = await backupDir();
    final d = Directory(dir);
    if (!await d.exists()) return [];
    final out = <BackupInfo>[];
    await for (final f in d.list()) {
      if (f is File && p.basename(f.path).startsWith('JSH_backup_')) {
        out.add(BackupInfo.fromFile(f));
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  static Future<List<BackupInfo>> listAuto() async =>
      (await listAll()).where((b) => b.kind == BackupKind.auto).toList();

  static Future<List<BackupInfo>> listManual() async =>
      (await listAll()).where((b) => b.kind == BackupKind.manual).toList();

  /// حذف خودکار بک‌آپ‌های اتوماتیک قدیمی‌تر از ۳۰ روز
  static Future<int> cleanupAutoBackups({int days = 30}) async {
    final autos = await listAuto();
    final limit = DateTime.now().subtract(Duration(days: days));
    var removed = 0;
    for (final b in autos) {
      if (b.createdAt.isBefore(limit)) {
        try {
          await File(b.path).delete();
          removed++;
        } catch (_) {}
      }
    }
    return removed;
  }

  static Future<void> deleteBackup(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  /// بازیابی — بانک می‌بندد، فایل جایگزین و دوباره باز می‌شود
  static Future<void> restoreBackup(String path) async {
    final f = File(path);
    if (!await f.exists()) throw Exception('فایل بک‌آپ یافت نشد');
    await Db.reset();
    final target = await Db.dbPath();
    await f.copy(target);
    await Db.instance();
  }

  /// پاک‌سازی کامل دیتابیس (فقط سوپروایزر) — رکورد لایسنس حفظ می‌شود
  static Future<void> wipeAllData() async {
    final db = await Db.instance();
    final tables = [
      'reminders', 'email_queue', 'payments', 'invoices', 'warranties',
      'ticket_items', 'ticket_status_log', 'tickets', 'devices', 'customers',
      'parts', 'settings',
    ];
    for (final t in tables) {
      await db.delete(t);
    }
    await db.execute('VACUUM');
  }
}
