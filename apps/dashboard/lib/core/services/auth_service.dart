/// فاز ۲ — کاربران، دسترسی تفکیکی و اکانت سازنده (بند ۸ + بند ۲ جدید — قاعده ۱۲)
///
/// - رمز اکانت سازنده هرگز در سورس نیست؛ فقط هش SHA-256 با نمک ثابت برنامه.
/// - اکانت سازنده: دسترسی کامل، غیرقابل حذف و غیرقابل ویرایش توسط دیگران،
///   در فهرست کاربران با نقش «سازنده» دیده می‌شود و هر عملیاتش در audit_log ثبت می‌شود.
/// - هر کاربر عادی می‌تواند دسترسی جداگانه به تک‌تک صفحات و عملیات‌ها بگیرد
///   (مثال بند ۸: کاربری که فقط سفارش ثبت می‌کند، تسویه می‌کند و فقط وضعیت را
///   از پذیرش به تشخیص تغییر می‌دهد).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../db/db.dart';
import '../repos.dart';
import 'supervisor_service.dart' show AuditRepo;

// ─────────────────────────────────────────────────────────────────────────────
// نقش‌ها
// ─────────────────────────────────────────────────────────────────────────────
const String kRoleCreator = 'creator';
const String kRoleAdmin = 'admin';
const String kRoleUser = 'user';

/// فهرست کلیدهای دسترسی — صفحات
class PermPages {
  static const List<Map<String, String>> all = [
    {'key': 'page.home', 'label': 'خانه'},
    {'key': 'page.intake', 'label': 'پذیرش'},
    {'key': 'page.orders', 'label': 'سفارشات'},
    {'key': 'page.board', 'label': 'کارتابل'},
    {'key': 'page.customers', 'label': 'مشتریان'},
    {'key': 'page.invoices', 'label': 'فاکتورها'},
    {'key': 'page.cashbox', 'label': 'صندوق'},
    {'key': 'page.calendar', 'label': 'تقویم'},
    {'key': 'page.reminders', 'label': 'یادآوری‌ها'},
    {'key': 'page.assistant', 'label': 'دستیار'},
    {'key': 'page.warranty', 'label': 'گارانتی'},
    {'key': 'page.dbmanager', 'label': 'دیتابیس'},
    {'key': 'page.users', 'label': 'مدیریت کاربران'},
    {'key': 'page.settings', 'label': 'تنظیمات'},
    {'key': 'page.theme', 'label': 'تم و ظاهر'},
    {'key': 'page.support', 'label': 'پشتیبانی'},
  ];

  static String labelOf(String key) => all
      .firstWhere((e) => e['key'] == key, orElse: () => {'label': key})['label']!;
}

/// فهرست کلیدهای دسترسی — عملیات‌های حساس
class PermActions {
  static const List<Map<String, String>> all = [
    {'key': 'action.intake.create', 'label': 'ثبت پذیرش جدید'},
    {'key': 'action.ticket.settle', 'label': 'تسویه حساب سفارش (دریافت وجه)'},
    {'key': 'action.delegation.assign', 'label': 'واگذاری سفارش به کاربر'},
    {'key': 'action.status.revert', 'label': 'برگشت وضعیت به مرحله قبل'},
    {'key': 'action.invoice.edit', 'label': 'ویرایش/ابطال فاکتور و پیش‌فاکتور'},
  ];

  static String labelOf(String key) => all
      .firstWhere((e) => e['key'] == key, orElse: () => {'label': key})['label']!;
}

/// گذارهای وضعیت کارتابل — فقط رو به جلو؛ برگشت با قاعده «فقط تغییردهنده»
/// + دسترسی action.status.revert کنترل می‌شود.
class PermTransitions {
  static const List<Map<String, String>> all = [
    {'key': 'status.intake__diagnosis', 'label': 'پذیرش ← تشخیص'},
    {'key': 'status.diagnosis__waiting_part', 'label': 'تشخیص ← انتظار قطعه'},
    {'key': 'status.waiting_part__repairing', 'label': 'انتظار قطعه ← تعمیر'},
    {'key': 'status.repairing__testing', 'label': 'تعمیر ← تست'},
    {'key': 'status.testing__ready', 'label': 'تست ← آماده تحویل'},
    {'key': 'status.ready__delivered', 'label': 'آماده تحویل ← تحویل شده'},
  ];

  static String keyFor(String from, String to) => 'status.${from}__$to';

  static String labelOf(String key) => all
      .firstWhere((e) => e['key'] == key, orElse: () => {'label': key})['label']!;
}

// ─────────────────────────────────────────────────────────────────────────────
// کاربر جاری نشست
// ─────────────────────────────────────────────────────────────────────────────
class AuthUser {
  final int id;
  final String username;
  final String displayName;
  final String role;
  final bool isActive;
  final Set<String> perms;

  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.isActive,
    this.perms = const {},
  });

  bool get isCreator => role == kRoleCreator;
  bool get isAdmin => role == kRoleAdmin || isCreator;
  String get roleLabelFa =>
      isCreator ? 'سازنده' : (role == kRoleAdmin ? 'مدیر' : 'کاربر');

  /// بررسی دسترسی — مدیر و سازنده همه‌چیز دارند؛ کاربر عادی فقط کلیدهای ثبت‌شده
  bool can(String permKey) => isAdmin || perms.contains(permKey);

  String get bestName => displayName.isEmpty ? username : displayName;
}

// ─────────────────────────────────────────────────────────────────────────────
// سرویس احراز هویت
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {
  /// اکانت سازنده — فقط هش + نمک در سورس (قاعده ۱۲ و بند ۲ جدید)
  /// نام کاربری سازنده در فهرست کاربران دیده می‌شود؛ رمز هرگز قابل بازیابی نیست.
  static const String creatorUsername = 'kyanoosh27993';
  static const String creatorSalt = '1f81928ce3c48347';
  static const String creatorHash =
      'affa4857add70a58b85618537ec216b665dabad7c3d02f381f71d99f264a1f82';
  static const String _creatorSalt = creatorSalt;
  static const String _creatorHash = creatorHash;

  /// نام کاربری اکانت مدیر پیش‌فرض (بند ۸ — admin/admin)
  static const String defaultAdminUsername = 'admin';
  static const String defaultAdminPassword = 'admin';

  // قفل تلاش‌های ناموفق — فقط در حافظه نشست (الگوی سوپروایزر)
  static int _fails = 0;
  static DateTime? _lockedUntil;

  static bool get isLockedNow =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
  static int get failCount => _fails;

  static String hash(String salt, String password) =>
      sha256.convert(utf8.encode(salt + password)).toString();

  static String randomSalt() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// بذر اکانت‌های اولیه — ایده‌مپوتنت؛ هرگز کاربر موجود را بازنویسی نمی‌کند
  static Future<void> ensureSeeded() async {
    final db = await Db.instance();
    final now = DateTime.now().toIso8601String();

    // اکانت سازنده — غیرقابل حذف/ویرایش، دسترسی کامل (نقش creator)
    final creatorRows = await db.query('users',
        where: 'username = ?', whereArgs: [creatorUsername], limit: 1);
    if (creatorRows.isEmpty) {
      await db.insert('users', {
        'username': creatorUsername,
        'display_name': 'سازنده برنامه',
        'role': kRoleCreator,
        'salt': _creatorSalt,
        'password_hash': _creatorHash,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await AuditRepo.log('user_seed',
          'اکانت سازنده ($creatorUsername) بر پایه قاعده ۱۲ ایجاد شد — فقط هش ذخیره شده است');
    }

    // اکانت مدیر پیش‌فرض admin/admin — بند ۸
    final adminRows = await db.query('users',
        where: 'username = ?', whereArgs: [defaultAdminUsername], limit: 1);
    if (adminRows.isEmpty) {
      final salt = randomSalt();
      await db.insert('users', {
        'username': defaultAdminUsername,
        'display_name': 'مدیر سیستم',
        'role': kRoleAdmin,
        'salt': salt,
        'password_hash': hash(salt, defaultAdminPassword),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  /// ورود کاربر — خروجی: (کاربر، پیام خطا)؛ کاربر فقط وقتی فعال است
  static Future<(AuthUser?, String)> login(
      String username, String password) async {
    final u = username.trim();
    if (u.isEmpty || password.isEmpty) {
      return (null, 'نام کاربری و رمز عبور را وارد کنید');
    }
    if (isLockedNow) {
      return (null, 'به دلیل تلاش‌های ناموفق، ورود موقتاً قفل است. چند دقیقه دیگر تلاش کنید.');
    }
    final row = await UserRepo.byUsernameRow(u);
    if (row == null) {
      _fails++;
      await AuditRepo.log('login_fail', 'نام کاربری ناموجود: $u');
      return (null, 'نام کاربری یا رمز عبور اشتباه است');
    }
    final stored = (row['password_hash'] ?? '') as String;
    final salt = (row['salt'] ?? '') as String;
    if (stored.isEmpty || hash(salt, password) != stored) {
      _fails++;
      await AuditRepo.log('login_fail', 'رمز اشتباه برای $u — تلاش #$_fails');
      if (_fails >= 5) {
        _lockedUntil = DateTime.now().add(const Duration(minutes: 5));
        await AuditRepo.log('login_lockout',
            '۵ تلاش ناموفق ورود — قفل موقت ۵ دقیقه (کاربر: $u)');
        return (null, '۵ تلاش ناموفق — ورود ۵ دقیقه قفل شد');
      }
      return (null, 'نام کاربری یا رمز عبور اشتباه است');
    }
    if (((row['is_active'] ?? 1) as int) != 1) {
      await AuditRepo.log('login_fail', 'اکانت غیرفعال: $u');
      return (null, 'این اکانت غیرفعال است — با مدیر سیستم تماس بگیرید');
    }
    _fails = 0;
    _lockedUntil = null;
    final user = AuthUser(
      id: row['id'] as int,
      username: (row['username'] ?? '') as String,
      displayName: (row['display_name'] ?? '') as String,
      role: (row['role'] ?? kRoleUser) as String,
      isActive: true,
      perms: (await UserRepo.permsOf(row['id'] as int)).toSet(),
    );
    await AuditRepo.log('login', 'ورود موفق: ${user.username} (${user.roleLabelFa})');
    return (user, '');
  }

  /// خروج کاربر — ثبت در حسابرسی
  static Future<void> logout(AuthUser u) async {
    await AuditRepo.log('logout', 'خروج: ${u.username}');
  }
}

/// بذر اکانت‌ها — از Db.instance() فراخوانی می‌شود تا هر نصب/بازیابی، کاربران
/// پایه را داشته باشد (ایده‌مپوتنت).
class AuthSeed {
  static Future<void> ensure() => AuthService.ensureSeeded();
}
