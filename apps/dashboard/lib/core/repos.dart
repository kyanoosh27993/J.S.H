/// لایه دسترسی به داده — ریپازیتوری‌های برنامه
library;

import 'db/db.dart';
import 'models.dart';
import 'services/auth_service.dart' show AuthUser, AuthService, kRoleCreator;
import 'services/supervisor_service.dart' show AuditRepo;
import 'package:shamsi_date/shamsi_date.dart' as j;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SettingsRepo {
  static Future<Map<String, String>> all() async {
    final db = await Db.instance();
    final rows = await db.query('settings');
    return {
      for (final r in rows) (r['key'] as String): (r['value'] ?? '') as String,
    };
  }

  static Future<String> get(String key, [String def = '']) async {
    final db = await Db.instance();
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return def;
    return (rows.first['value'] ?? '') as String;
  }

  static Future<void> set(String key, String value) async {
    final db = await Db.instance();
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class CustomerRepo {
  static Future<int> insert(Customer c) async {
    final db = await Db.instance();
    return db.insert('customers', c.toMap());
  }

  static Future<void> update(Customer c) async {
    final db = await Db.instance();
    await db.update('customers', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  static Future<List<Customer>> search(String q) async {
    final db = await Db.instance();
    final like = '%$q%';
    // بند ۱۰ — جستجو در همه فیلدهای مهم مشتری
    final rows = await db.query(
      'customers',
      where: q.isEmpty
          ? null
          : 'name LIKE ? OR phone LIKE ? OR national_id LIKE ? OR '
              'father_name LIKE ? OR tag LIKE ? OR address LIKE ?',
      whereArgs: q.isEmpty ? null : [like, like, like, like, like, like],
      orderBy: 'id DESC',
      limit: 200,
    );
    return rows.map(Customer.fromMap).toList();
  }

  static Future<Customer?> byId(int id) async {
    final db = await Db.instance();
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// نقشه id→نام همه مشتریان — برای کارتابل لیستی (قاعده ۱۱: یک کوئری به‌جای N+1)
  static Future<Map<int, String>> nameMap() async {
    final db = await Db.instance();
    final rows = await db.query('customers', columns: ['id', 'name']);
    return {
      for (final r in rows) (r['id'] as int): (r['name'] ?? '') as String,
    };
  }
}

class DeviceRepo {
  static Future<int> insert(Device d) async {
    final db = await Db.instance();
    return db.insert('devices', d.toMap());
  }

  static Future<Device?> byId(int id) async {
    final db = await Db.instance();
    final rows = await db.query('devices', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Device.fromMap(rows.first);
  }

  static Future<List<Device>> byCustomer(int customerId) async {
    final db = await Db.instance();
    final rows = await db.query('devices',
        where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id DESC');
    return rows.map(Device.fromMap).toList();
  }
}

class TicketRepo {
  static Future<int> insert(Ticket t) async {
    final db = await Db.instance();
    final id = await db.insert('tickets', t.toMap());
    return id;
  }

  static Future<void> update(Ticket t) async {
    t.updatedAt = DateTime.now().toIso8601String();
    final db = await Db.instance();
    await db.update('tickets', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
  }

  /// حذف کامل سفارش با وابستگی‌ها
  static Future<void> delete(int id) async {
    final db = await Db.instance();
    final t = await byId(id);
    if (t == null) return;
    final items = await db.query('ticket_items',
        columns: ['id'], where: 'ticket_id = ?', whereArgs: [id]);
    for (final it in items) {
      await db.delete('warranties',
          where: 'ticket_item_id = ?', whereArgs: [it['id']]);
    }
    await db.delete('invoices', where: 'ticket_id = ?', whereArgs: [id]);
    await db
        .delete('ticket_items', where: 'ticket_id = ?', whereArgs: [id]);
    await db.delete('payments', where: 'ticket_id = ?', whereArgs: [id]);
    await db.delete('ticket_status_log',
        where: 'ticket_id = ?', whereArgs: [id]);
    await db.delete('tickets', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Ticket?> byId(int id) async {
    final db = await Db.instance();
    final rows = await db.query('tickets', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Ticket.fromMap(rows.first);
  }

  static Future<List<Ticket>> all({String? status}) async {
    final db = await Db.instance();
    final rows = await db.query('tickets',
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status],
        orderBy: 'id DESC');
    return rows.map(Ticket.fromMap).toList();
  }

  static Future<List<Ticket>> dueBetween(DateTime from, DateTime to) async {
    final db = await Db.instance();
    final rows = await db.query('tickets',
        where: 'due_date >= ? AND due_date < ? AND status != ?',
        whereArgs: [from.toIso8601String(), to.toIso8601String(), 'delivered'],
        orderBy: 'due_date ASC');
    return rows.map(Ticket.fromMap).toList();
  }

  static Future<String> nextCode() async {
    final db = await Db.instance();
    // بند ۱۲ نسخه ۳ — شماره رسید بر اساس تاریخ شمسی (مانند شماره فاکتور)
    final jd = j.Jalali.fromDateTime(DateTime.now());
    final prefix =
        'RCP-${jd.year}${jd.month.toString().padLeft(2, '0')}${jd.day.toString().padLeft(2, '0')}-';
    final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM tickets WHERE code LIKE ?", ['$prefix%']);
    final n = ((rows.first['c'] ?? 0) as int) + 1;
    return '$prefix${n.toString().padLeft(3, '0')}';
  }

  /// تغییر وضعیت با ثبت کاربر، دلیل و واگذاری — فاز ۲ (بند ۸)
  /// userId = 0 یعنی سیستم (بدون کاربر — سازگاری با کدهای قبلی)
  static Future<void> changeStatus(int ticketId, String to,
      {int userId = 0,
      String reason = '',
      String note = '',
      int? assignTo}) async {
    final t = await byId(ticketId);
    if (t == null) return;
    final from = t.status;
    t.status = to;
    if (assignTo != null) {
      t.assignedTo = assignTo;
      t.assignedBy = userId;
      t.assignedAt = DateTime.now().toIso8601String();
    }
    await update(t);
    final db = await Db.instance();
    await db.insert('ticket_status_log', {
      'ticket_id': ticketId,
      'status': to, // ستون قدیمی — سازگاری با کد قبلی
      'from_status': from,
      'to_status': to,
      'reason': reason,
      'note': note,
      'user_id': userId,
      'assigned_to': assignTo,
      'created_at': DateTime.now().toIso8601String(),
    });
    await AuditRepo.log('status_change',
        'سفارش #$ticketId: $from ← $to — کاربر #$userId${reason.isEmpty ? '' : ' — دلیل: $reason'}');
  }

  static Future<List<Map<String, Object?>>> statusLog(int ticketId) async {
    final db = await Db.instance();
    return db.query('ticket_status_log',
        where: 'ticket_id = ?', whereArgs: [ticketId], orderBy: 'id ASC');
  }

  /// واگذاری بدون تغییر وضعیت — پذیرش‌کننده کار را به شخص خاص می‌سپارد (بند ۸)
  static Future<void> assign(
      int ticketId, int assignTo, int byUserId) async {
    final t = await byId(ticketId);
    if (t == null) return;
    t.assignedTo = assignTo;
    t.assignedBy = byUserId;
    t.assignedAt = DateTime.now().toIso8601String();
    await update(t);
    final db = await Db.instance();
    await db.insert('ticket_status_log', {
      'ticket_id': ticketId,
      'status': t.status,
      'from_status': t.status,
      'to_status': t.status,
      'reason': 'واگذاری سفارش به کاربر #$assignTo',
      'user_id': byUserId,
      'assigned_to': assignTo,
      'created_at': DateTime.now().toIso8601String(),
    });
    await AuditRepo.log('ticket_assign',
        'سفارش #$ticketId به کاربر #$assignTo واگذار شد — توسط #$byUserId');
  }

  /// قاعده بند ۸: برگشت وضعیت فقط توسط کاربری که آخرین تغییر را داده
  /// (مدیر و سازنده همیشه مجازند)
  static Future<bool> canRevert(int ticketId, AuthUser? u) async {
    if (u == null) return false;
    if (u.isAdmin) return true;
    final db = await Db.instance();
    final rows = await db.query('ticket_status_log',
        where: 'ticket_id = ?',
        whereArgs: [ticketId],
        orderBy: 'id DESC',
        limit: 1);
    if (rows.isEmpty) return false;
    return (rows.first['user_id'] ?? 0) == u.id;
  }

  /// گزارش عملکرد کاربران در بازه تاریخی (بند ۸ — مقایسه عملکرد)
  /// خروجی: نام، تعداد تغییر وضعیت، پذیرش، تحویل، وصولی، سهم درصدی
  static Future<List<Map<String, Object?>>> activityReport(
      String fromIso, String toIso) async {
    final db = await Db.instance();
    final rows = await db.rawQuery('''
      SELECT u.id, u.username, u.display_name, u.role,
        (SELECT COUNT(*) FROM ticket_status_log l
          WHERE l.user_id = u.id AND l.created_at >= ? AND l.created_at < ?
            AND l.from_status != l.to_status) AS changes,
        (SELECT COUNT(*) FROM ticket_status_log l
          WHERE l.user_id = u.id AND l.created_at >= ? AND l.created_at < ?
            AND l.to_status = 'intake') AS accepted,
        (SELECT COUNT(*) FROM ticket_status_log l
          WHERE l.user_id = u.id AND l.created_at >= ? AND l.created_at < ?
            AND l.to_status = 'delivered') AS delivered,
        (SELECT COUNT(*) FROM tickets t
          WHERE t.created_by = u.id AND t.created_at >= ? AND t.created_at < ?) AS intakes,
        (SELECT COALESCE(SUM(p.amount), 0) FROM payments p
          WHERE p.user_id = u.id AND p.created_at >= ? AND p.created_at < ?) AS collected
      FROM users u
      ORDER BY u.id ASC
    ''', [
      fromIso, toIso,
      fromIso, toIso,
      fromIso, toIso,
      fromIso, toIso,
      fromIso, toIso,
    ]);
    final total = rows.fold<int>(
        0, (s, r) => s + ((r['collected'] ?? 0) as int));
    return [
      for (final r in rows)
        {
          ...r,
          'share': total > 0
              ? (((r['collected'] ?? 0) as int) * 100 / total)
              : 0.0,
        }
    ];
  }
}

/// ریپازیتوری کاربران و دسترسی‌ها — فاز ۲ (بند ۸ + قاعده ۱۲)
class UserRepo {
  /// فهرست کاربران — بدون هش رمز
  static Future<List<Map<String, Object?>>> list() async {
    final db = await Db.instance();
    return db.query('users', columns: [
      'id',
      'username',
      'display_name',
      'role',
      'is_active',
      'created_at',
      'updated_at',
    ], orderBy: 'id ASC');
  }

  static Future<Map<String, Object?>?> byUsernameRow(String username) async {
    final db = await Db.instance();
    final rows = await db.query('users',
        where: 'username = ?',
        whereArgs: [username.trim()],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<AuthUser?> byId(int id) async {
    final db = await Db.instance();
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return AuthUser(
      id: r['id'] as int,
      username: (r['username'] ?? '') as String,
      displayName: (r['display_name'] ?? '') as String,
      role: (r['role'] ?? 'user') as String,
      isActive: ((r['is_active'] ?? 1) as int) == 1,
      perms: (await permsOf(id)).toSet(),
    );
  }

  /// نام نمایشی کاربر — برای کارت‌های کارتابل و گزارش‌ها
  static Future<String> displayNameOf(int id) async {
    final db = await Db.instance();
    final rows = await db.query('users',
        columns: ['username', 'display_name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    if (rows.isEmpty) return '';
    final dn = (rows.first['display_name'] ?? '') as String;
    return dn.isEmpty ? ((rows.first['username'] ?? '') as String) : dn;
  }

  /// افزودن کاربر — خروجی: (id یا null، پیام خطا)
  static Future<(int?, String)> create({
    required String username,
    required String displayName,
    required String role,
    required String password,
  }) async {
    final u = username.trim();
    if (u.isEmpty) return (null, 'نام کاربری الزامی است');
    if (password.length < 4) return (null, 'رمز عبور حداقل ۴ نویسه باشد');
    if (await byUsernameRow(u) != null) {
      return (null, 'این نام کاربری قبلاً ثبت شده است');
    }
    final salt = AuthService.randomSalt();
    final db = await Db.instance();
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('users', {
      'username': u,
      'display_name': displayName.trim(),
      'role': role,
      'salt': salt,
      'password_hash': AuthService.hash(salt, password),
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await AuditRepo.log('user_create', 'کاربر "$u" با نقش $role ایجاد شد');
    return (id, '');
  }

  /// تغییر پروفایل — اکانت سازنده از بیرون قابل تغییر نیست (قاعده ۱۲)
  static Future<String?> updateProfile(
      {required int id,
      required String displayName,
      required String role,
      required bool isActive,
      required AuthUser? actor}) async {
    final db = await Db.instance();
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return 'کاربر یافت نشد';
    if ((rows.first['role'] ?? '') == kRoleCreator) {
      return 'اکانت سازنده قابل ویرایش نیست';
    }
    if (actor != null && actor.id == id && !isActive) {
      return 'نمی‌توانید اکانت خودتان را غیرفعال کنید';
    }
    await db.update('users', {
      'display_name': displayName.trim(),
      'role': role,
      'is_active': isActive ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('user_update', 'ویرایش کاربر #$id');
    return null;
  }

  /// تغییر نام کاربری — بند ۸: مدیر باید بتواند نام کاربری خودش را عوض کند
  static Future<String?> setUsername(
      {required int id, required String username, required AuthUser? actor}) async {
    final u = username.trim();
    if (u.isEmpty) return 'نام کاربری الزامی است';
    final db = await Db.instance();
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return 'کاربر یافت نشد';
    if ((rows.first['role'] ?? '') == kRoleCreator) {
      return 'نام کاربری اکانت سازنده قابل تغییر نیست';
    }
    final clash = await byUsernameRow(u);
    if (clash != null && (clash['id'] as int) != id) {
      return 'این نام کاربری قبلاً ثبت شده است';
    }
    await db.update('users', {
      'username': u,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log(
        'user_rename', 'تغییر نام کاربری #$id به «$u» — توسط ${actor?.username ?? '-'}');
    return null;
  }

  /// تغییر رمز — سازنده قابل تغییر نیست
  static Future<String?> setPassword(
      {required int id, required String password}) async {
    if (password.length < 4) return 'رمز عبور حداقل ۴ نویسه باشد';
    final db = await Db.instance();
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return 'کاربر یافت نشد';
    if ((rows.first['role'] ?? '') == kRoleCreator) {
      return 'رمز اکانت سازنده قابل تغییر نیست';
    }
    final salt = AuthService.randomSalt();
    await db.update('users', {
      'salt': salt,
      'password_hash': AuthService.hash(salt, password),
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('user_password', 'تغییر رمز کاربر #$id');
    return null;
  }

  /// حذف کاربر — سازنده هرگز حذف نمی‌شود (قاعده ۱۲)
  static Future<String?> delete(int id, {AuthUser? actor}) async {
    final db = await Db.instance();
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return 'کاربر یافت نشد';
    if ((rows.first['role'] ?? '') == kRoleCreator) {
      return 'اکانت سازنده قابل حذف نیست';
    }
    if (actor != null && actor.id == id) {
      return 'نمی‌توانید اکانت خودتان را حذف کنید';
    }
    await db.delete('user_permissions', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('user_delete', 'حذف کاربر #$id');
    return null;
  }

  static Future<List<String>> permsOf(int userId) async {
    final db = await Db.instance();
    final rows = await db.query('user_permissions',
        columns: ['perm_key'], where: 'user_id = ?', whereArgs: [userId]);
    return rows.map((r) => (r['perm_key'] ?? '') as String).toList();
  }

  static Future<void> setPerms(int userId, List<String> keys) async {
    final db = await Db.instance();
    await db.delete('user_permissions', where: 'user_id = ?', whereArgs: [userId]);
    for (final k in keys) {
      await db
          .insert('user_permissions', {'user_id': userId, 'perm_key': k});
    }
    await AuditRepo.log('user_perms',
        'دسترسی‌های کاربر #$userId به‌روزرسانی شد (${keys.length} کلید)');
  }
}

class TicketItemRepo {
  static Future<int> insert(TicketItem i) async {
    final db = await Db.instance();
    return db.insert('ticket_items', i.toMap());
  }

  static Future<List<TicketItem>> byTicket(int ticketId) async {
    final db = await Db.instance();
    final rows = await db.query('ticket_items',
        where: 'ticket_id = ?', whereArgs: [ticketId], orderBy: 'id ASC');
    return rows.map(TicketItem.fromMap).toList();
  }

  static Future<void> delete(int id) async {
    final db = await Db.instance();
    await db.delete('ticket_items', where: 'id = ?', whereArgs: [id]);
  }

  /// جمع price*qty هر سفارش در یک کوئری — بهینه‌سازی عملکرد (قاعده ۱۱)
  static Future<Map<int, int>> sumsForAllTickets() async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        "SELECT ticket_id, COALESCE(SUM(price * qty), 0) AS s FROM ticket_items "
        "WHERE COALESCE(item_type, '') != 'damage' GROUP BY ticket_id");
    return {
      for (final r in rows) (r['ticket_id'] as int): (r['s'] as int),
    };
  }
}

class PaymentRepo {
  static Future<int> insert(Payment p) async {
    final db = await Db.instance();
    return db.insert('payments', p.toMap());
  }

  static Future<List<Payment>> byTicket(int ticketId) async {
    final db = await Db.instance();
    final rows = await db.query('payments',
        where: 'ticket_id = ?', whereArgs: [ticketId], orderBy: 'id ASC');
    return rows.map(Payment.fromMap).toList();
  }

  static Future<int> paidSum(int ticketId) async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM payments WHERE ticket_id = ?',
        [ticketId]);
    return (rows.first['s'] ?? 0) as int;
  }

  /// تجمیع یک‌باره برای همه سفارش‌ها — بهینه‌سازی عملکرد (قاعده ۱۱)
  static Future<Map<int, int>> paidSumForAll() async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        'SELECT ticket_id, COALESCE(SUM(amount), 0) AS s FROM payments GROUP BY ticket_id');
    return {
      for (final r in rows) (r['ticket_id'] as int): (r['s'] as int),
    };
  }
}

class ReminderRepo {
  static Future<int> insert(Reminder r) async {
    final db = await Db.instance();
    return db.insert('reminders', r.toMap());
  }

  static Future<List<Reminder>> pendingBefore(DateTime limit) async {
    final db = await Db.instance();
    final rows = await db.query('reminders',
        where: "status = 'pending' AND remind_at <= ?",
        whereArgs: [limit.toIso8601String()],
        orderBy: 'remind_at ASC');
    return rows.map(Reminder.fromMap).toList();
  }

  static Future<void> markShown(int id) async {
    final db = await Db.instance();
    await db.update('reminders', {'status': 'shown'},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<Reminder?> forTicket(int ticketId, {String type = 'delivery'}) async {
    final db = await Db.instance();
    final rows = await db.query('reminders',
        where: 'ticket_id = ? AND type = ?', whereArgs: [ticketId, type],
        limit: 1);
    return rows.isEmpty ? null : Reminder.fromMap(rows.first);
  }
}

class LicenseRepo {
  static Future<LicenseState> load() async {
    final db = await Db.instance();
    final rows = await db.query('license_state', limit: 1);
    if (rows.isEmpty) {
      final fresh = LicenseState(
        firstRunAt: DateTime.now().toIso8601String(),
      );
      await db.insert('license_state', {
        'id': 1,
        'install_count': fresh.installCount,
        'first_run_at': fresh.firstRunAt,
        'report_status': 'pending',
      });
      return fresh;
    }
    return LicenseState.fromMap(rows.first);
  }

  static Future<void> save(LicenseState s) async {
    final db = await Db.instance();
    // UPSERT — رکورد ممکن است در نصب تازه هنوز ساخته نشده باشد
    await db.insert('license_state', {
      'id': 1,
      'install_count': s.installCount,
      'fingerprint': s.fingerprint,
      'consented_at': s.consentedAt,
      'user_email': s.userEmail,
      'buyer_name': s.buyerName,
      'report_status': s.reportStatus,
      'report_sent_at': s.reportSentAt,
      'last_report_error': s.lastReportError,
      'hardware_report': s.hardwareReport,
      'first_run_at': s.firstRunAt,
      'activation_code': s.activationCode,
      'activation_expiry': s.activationExpiry,
      'activated_at': s.activatedAt,
      'last_seen_date': s.lastSeenDate,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

/// ریپازیتوری فاکتور — فاز ۵ (بندهای ۱۲ و ۱۳)
/// شماره‌گذاری استاندارد: سال+روز ثبت (شمسی YYYYMMDD) + عدد افزاینده ۴ رقمی
/// که شروع آن در تنظیمات تعیین می‌شود؛ ابطال به‌جای حذف؛ حذف کامل فقط مدیر اصلی.
class InvoiceRepo {
  static const String kindPre = 'pre';
  static const String kindFinal = 'final';

  static Future<Map<int, Map<String, Object?>>> allByTicketMap() async {
    final db = await Db.instance();
    final rows = await db.query('invoices', orderBy: 'id DESC');
    return {for (final r in rows) (r['ticket_id'] as int): r};
  }

  /// شماره استاندارد — YYYYMMDD-#### (بند ۱۲)
  static Future<String> nextNumber(String kind) async {
    final db = await Db.instance();
    final now = DateTime.now();
    final jd = j.Jalali.fromDateTime(now);
    final datePrefix =
        '${jd.year}${jd.month.toString().padLeft(2, '0')}${jd.day.toString().padLeft(2, '0')}';
    final settingKey = kind == kindPre ? 'pre_invoice_start' : 'invoice_start';
    final start = int.tryParse(
            await SettingsRepo.get(settingKey, '1')) ??
        1;
    final rows = await db.query('invoices',
        columns: ['number'],
        where: 'number LIKE ? AND kind = ?',
        whereArgs: ['$datePrefix-%', kind]);
    final maxSeq = rows.fold<int>(0, (mx, r) {
      final n = (r['number'] ?? '') as String;
      final seqPart = n.split('-').last;
      return mx < (int.tryParse(seqPart) ?? 0) ? (int.tryParse(seqPart) ?? 0) : mx;
    });
    final seq = start > maxSeq ? start : maxSeq + 1;
    return '$datePrefix-${seq.toString().padLeft(4, '0')}';
  }

  /// ساخت فاکتور از سفارش — پیش‌فاکتور یا قطعی
  /// فاز ۵b (بند ۱۲): پارامترهای اختیاری هزینه/تخفیف/خسارت + کاربر خسارت‌زننده
  /// و یادداشت سود — برای فاکتور قطعی از دیالوگ «صدور سند» پر می‌شود.
  static Future<int> createFromTicket({
    required Ticket ticket,
    required String kind,
    int discount = 0,
    String note = '',
    int? cost,
    int? damage,
    int? damageUserId,
    String? profitNote,
  }) async {
    final db = await Db.instance();
    final items = await TicketItemRepo.byTicket(ticket.id!);
    // قلم «خسارت» اطلاعاتی است و در جمع حساب نمی‌شود (بند ۱۰.۶۹)
    final sum = items
        .where((i) => i.countsInTotal)
        .fold<int>(0, (s, i) => s + i.price * i.qty);
    final total = sum > 0 ? sum : ticket.estimateAmount;
    final paid = await PaymentRepo.paidSum(ticket.id!);
    final existing = await db.query('invoices',
        where: 'ticket_id = ? AND kind = ?',
        whereArgs: [ticket.id!, kind],
        limit: 1);
    if (existing.isNotEmpty) {
      // فاز ۵ — سند موجود به‌روز می‌شود (جمع/پرداخت/مانده) نه تکراری
      final id = existing.first['id'] as int;
      final disc = discount > 0 ? discount : (existing.first['discount'] ?? 0) as int;
      final upd = <String, Object?>{
        'total': total,
        'paid': paid,
        'remaining': (total - disc) - paid,
      };
      if (cost != null) upd['cost'] = cost;
      if (damage != null) {
        upd['damage'] = damage;
        if (damageUserId != null) upd['damage_user'] = damageUserId;
      }
      if (profitNote != null && profitNote.isNotEmpty) {
        upd['profit_note'] = profitNote;
      }
      upd['updated_at'] = DateTime.now().toIso8601String();
      await db.update('invoices', upd, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    final number = await nextNumber(kind);
    final id = await db.insert('invoices', {
      'ticket_id': ticket.id!,
      'number': number,
      'total': total,
      'discount': discount,
      'paid': paid,
      'remaining': (total - discount) - paid,
      'issued_at': DateTime.now().toIso8601String(),
      'pdf_path': '',
      'kind': kind,
      'status': 'active',
      'cancelled_at': '',
      'cancel_reason': '',
      'note': note,
      'cost': cost ?? 0,
      'damage': damage ?? 0,
      if (damageUserId != null) 'damage_user': damageUserId,
      'profit_note': profitNote ?? '',
      'updated_at': DateTime.now().toIso8601String(),
    });
    await AuditRepo.log('invoice_create',
        'ساخت ${kind == kindPre ? 'پیش‌فاکتور' : 'فاکتور'} $number برای سفارش #${ticket.id}');
    return id;
  }

  /// سود خالص فاکتور (بند ۱۲) — جمع منهای تخفیف، هزینه و خسارت
  static int netProfitOf(Map<String, Object?> inv) =>
      ((inv['total'] ?? 0) as int) -
      ((inv['discount'] ?? 0) as int) -
      ((inv['cost'] ?? 0) as int) -
      ((inv['damage'] ?? 0) as int);

  /// اصلاح مبالغ فاکتور — بند ۱۲: هر تغییر با لاگ قدیمی/جدید برای مدیر سیستم
  static Future<void> updateFinancials(
    int id, {
    required int cost,
    required int discount,
    required int damage,
    int? damageUserId,
    String profitNote = '',
    int userId = 0,
  }) async {
    final db = await Db.instance();
    final rows =
        await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final r = rows.first;
    final total = (r['total'] ?? 0) as int;
    final paid = (r['paid'] ?? 0) as int;
    final oldCost = (r['cost'] ?? 0) as int;
    final oldDiscount = (r['discount'] ?? 0) as int;
    final oldDamage = (r['damage'] ?? 0) as int;
    await db.update('invoices', {
      'cost': cost,
      'discount': discount,
      'damage': damage,
      if (damageUserId != null) 'damage_user': damageUserId,
      'profit_note': profitNote,
      'remaining': (total - discount) - paid,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('invoice_cost_edit',
        'فاکتور #$id — قبلی: هزینه $oldCost، تخفیف $oldDiscount، خسارت $oldDamage / '
        'جدید: هزینه $cost، تخفیف $discount، خسارت $damage — کاربر #$userId');
  }

  /// فقط فاکتورهای فعال (غیر ابطالی) به‌ازای هر سفارش — بند ۲۳:
  /// فاکتور ابطالی نباید در صندوق/تسویه دیده شود.
  static Future<Map<int, Map<String, Object?>>> activeByTicketMap() async {
    final db = await Db.instance();
    final rows = await db.query('invoices',
        where: "COALESCE(status, '') != 'cancelled'", orderBy: 'id DESC');
    return {for (final r in rows) (r['ticket_id'] as int): r};
  }

  /// ابطال — هیچ فاکتوری حذف نمی‌شود (بند ۱۳)
  static Future<void> cancel(int id, String reason, {int userId = 0}) async {
    final db = await Db.instance();
    await db.update('invoices', {
      'status': 'cancelled',
      'cancelled_at': DateTime.now().toIso8601String(),
      'cancel_reason': reason,
    }, where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('invoice_cancel',
        'ابطال فاکتور #$id با دلیل: $reason — کاربر #$userId');
  }

  /// بازگردانی از ابطال — برای اشتباه ابطال
  static Future<void> restore(int id, {int userId = 0}) async {
    final db = await Db.instance();
    await db.update('invoices', {
      'status': 'active',
      'cancelled_at': '',
      'cancel_reason': '',
    }, where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('invoice_restore', 'بازگردانی فاکتور #$id — کاربر #$userId');
  }

  /// حذف کامل — فقط مدیر اصلی برنامه (بند ۱۳)
  /// همه ردپاهای سفارش مرتبط هم پاک می‌شوند: قلم‌ها، پرداخت‌ها، یادآورها،
  /// گارانتی‌ها، تاریخچه وضعیت و عکس‌های اتچ‌شده (بند ۲۳ — حذف کامل).
  static Future<String?> deleteFully(int id, {AuthUser? actor}) async {
    if (actor == null || !(actor.isAdmin)) {
      return 'حذف کامل فاکتور فقط توسط مدیر اصلی مجاز است';
    }
    final db = await Db.instance();
    final rows =
        await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final ticketId = (rows.first['ticket_id'] ?? 0) as int;
    final items = await db.query('ticket_items',
        columns: ['id'], where: 'ticket_id = ?', whereArgs: [ticketId]);
    for (final it in items) {
      await db.delete('warranties',
          where: 'ticket_item_id = ?', whereArgs: [it['id']]);
    }
    await db.delete('warranty_records', where: 'ticket_id = ?', whereArgs: [ticketId]);
    await db.delete('attachments', where: 'ticket_id = ?', whereArgs: [ticketId]);
    await db.delete('reminders', where: 'ticket_id = ?', whereArgs: [ticketId]);
    await db.delete('ticket_status_log',
        where: 'ticket_id = ?', whereArgs: [ticketId]);
    await db.delete('ticket_items', where: 'ticket_id = ?', whereArgs: [ticketId]);
    await db.delete('payments', where: 'ticket_id = ?', whereArgs: [ticketId]);
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
    await AuditRepo.log('invoice_delete',
        'حذف کامل فاکتور #$id و همه اثرهای سفارش #$ticketId — توسط ${actor.username}');
    return null;
  }

  /// افزودن قلم به فاکتور سفارش (صندوق — بند ۱۴) و به‌روزرسانی جمع
  static Future<void> refreshForTicket(int ticketId) async {
    final db = await Db.instance();
    final rows = await db.query('invoices',
        where: 'ticket_id = ?', whereArgs: [ticketId]);
    final ticket = await TicketRepo.byId(ticketId);
    if (ticket == null) return;
    final items = await TicketItemRepo.byTicket(ticketId);
    // قلم «خسارت» در جمع حساب نمی‌شود (بند ۱۰.۶۹)
    final sum = items
        .where((i) => i.countsInTotal)
        .fold<int>(0, (s, i) => s + i.price * i.qty);
    final total = sum > 0 ? sum : ticket.estimateAmount;
    final paid = await PaymentRepo.paidSum(ticketId);
    for (final r in rows) {
      if ((r['status'] ?? '') == 'cancelled') continue;
      final discount = (r['discount'] ?? 0) as int;
      await db.update('invoices', {
        'total': total,
        'paid': paid,
        'remaining': (total - discount) - paid,
      }, where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  /// اعمال تخفیف نقدی یا درصدی (بند ۱۴)
  static Future<void> applyDiscount(int invoiceId, {int amount = 0, double percent = 0}) async {
    final db = await Db.instance();
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (rows.isEmpty) return;
    final r = rows.first;
    final total = (r['total'] ?? 0) as int;
    final newDiscount = percent > 0
        ? ((total * percent / 100).round())
        : amount;
    final paid = (r['paid'] ?? 0) as int;
    await db.update('invoices', {
      'discount': newDiscount,
      'remaining': (total - newDiscount) - paid,
    }, where: 'id = ?', whereArgs: [invoiceId]);
    await AuditRepo.log('invoice_discount',
        'تخفیف $newDiscount تومان روی فاکتور #$invoiceId');
  }

  /// تسویه مانده (صندوق — بند ۱۴) — با کاربر وصول‌کننده
  static Future<void> settle(int invoiceId, int ticketId,
      {int? amount, int? userId}) async {
    final db = await Db.instance();
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (rows.isEmpty) return;
    final r = rows.first;
    final remaining = (r['remaining'] ?? 0) as int;
    final pay = amount ?? (remaining > 0 ? remaining : 0);
    if (pay <= 0) return;
    await PaymentRepo.insert(Payment(
      ticketId: ticketId,
      amount: pay,
      kind: 'final',
      userId: userId,
    ));
    await refreshForTicket(ticketId);
    await AuditRepo.log('settle', 'تسویه $pay تومان فاکتور #$invoiceId');
  }

  /// جستجو با شماره فاکتور یا کد سفارش — باز کردن سند (بند ۶ جدید)
  static Future<Map<String, Object?>?> findByNumberOrCode(String q) async {
    final db = await Db.instance();
    final like = '%${q.trim()}%';
    final rows = await db.rawQuery('''
      SELECT i.* FROM invoices i
      LEFT JOIN tickets t ON t.id = i.ticket_id
      WHERE i.number LIKE ? OR t.code LIKE ?
      ORDER BY i.id DESC LIMIT 1
    ''', [like, like]);
    return rows.isEmpty ? null : rows.first;
  }

  /// آخرین سند یک سفارش — برای نمایش QR در صفحه جزئیات (بند ۱۰.۶۷)
  static Future<Map<String, Object?>?> mainForTicket(int ticketId) async {
    final db = await Db.instance();
    final rows = await db.query('invoices',
        where: 'ticket_id = ?', whereArgs: [ticketId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }
}
