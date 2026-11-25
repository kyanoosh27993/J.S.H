/// لایه دسترسی به داده — ریپازیتوری‌های برنامه
library;

import 'db/db.dart';
import 'models.dart';
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
    final rows = await db.query(
      'customers',
      where: q.isEmpty
          ? null
          : 'name LIKE ? OR phone LIKE ? OR national_id LIKE ?',
      whereArgs: q.isEmpty ? null : [like, like, like],
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
    return db.insert('tickets', t.toMap());
  }

  static Future<void> update(Ticket t) async {
    t.updatedAt = DateTime.now().toIso8601String();
    final db = await Db.instance();
    await db.update('tickets', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
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
    final now = DateTime.now();
    final prefix =
        'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-';
    final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM tickets WHERE code LIKE ?", ['$prefix%']);
    final n = ((rows.first['c'] ?? 0) as int) + 1;
    return '$prefix${n.toString().padLeft(3, '0')}';
  }

  static Future<void> changeStatus(int ticketId, String status,
      {String note = ''}) async {
    final t = await byId(ticketId);
    if (t == null) return;
    t.status = status;
    await update(t);
    final db = await Db.instance();
    await db.insert('ticket_status_log', {
      'ticket_id': ticketId,
      'status': status,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, Object?>>> statusLog(int ticketId) async {
    final db = await Db.instance();
    return db.query('ticket_status_log',
        where: 'ticket_id = ?', whereArgs: [ticketId], orderBy: 'id ASC');
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

class EmailQueueRepo {
  static Future<int> enqueue({
    required String to,
    required String subject,
    required String body,
    String attachmentPath = '',
    String icsContent = '',
  }) async {
    final db = await Db.instance();
    return db.insert('email_queue', {
      'to_addr': to,
      'subject': subject,
      'body': body,
      'attachment_path': attachmentPath,
      'ics_content': icsContent,
      'status': 'pending',
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, Object?>>> pending({int limit = 10}) async {
    final db = await Db.instance();
    return db.query('email_queue',
        where: "status = 'pending'",
        orderBy: 'id ASC',
        limit: limit);
  }

  static Future<void> markSent(int id) async {
    final db = await Db.instance();
    await db.update('email_queue', {
      'status': 'sent',
      'sent_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markFailed(int id, String error) async {
    final db = await Db.instance();
    await db.rawUpdate(
      'UPDATE email_queue SET attempts = attempts + 1, last_error = ?, '
      "status = CASE WHEN attempts >= 20 THEN 'failed' ELSE 'pending' END "
      'WHERE id = ?',
      [error, id],
    );
  }

  static Future<bool> hasPending() async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM email_queue WHERE status = 'pending'");
    return ((rows.first['c'] ?? 0) as int) > 0;
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
    await db.update('license_state', {
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
    }, where: 'id = 1');
  }
}
