/// باز کردن و ساخت پایگاه‌داده SQLite محلی (آفلاین‌محور — F-02)
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// DDL کامل — جدول‌های فازهای بعدی هم از الان ساخته می‌شوند تا مهاجرت لازم نباشد.
const String kSchema = '''
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  father_name TEXT DEFAULT '',
  national_id TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  address TEXT DEFAULT '',
  tag TEXT DEFAULT '',
  note TEXT DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  model TEXT NOT NULL,
  category TEXT DEFAULT 'موبایل',
  serial TEXT DEFAULT '',
  note TEXT DEFAULT ''
);
CREATE TABLE IF NOT EXISTS tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  device_id INTEGER NOT NULL REFERENCES devices(id),
  intake_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  due_time TEXT DEFAULT '18:00',
  defect TEXT DEFAULT '',
  diagnosis TEXT DEFAULT '',
  phone_state TEXT DEFAULT '',
  estimate_amount INTEGER DEFAULT 0,
  deposit_amount INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'intake',
  accessories TEXT DEFAULT '[]',
  terms_accepted INTEGER DEFAULT 0,
  signature_path TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ticket_status_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  status TEXT NOT NULL,
  note TEXT DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ticket_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  kind TEXT NOT NULL DEFAULT 'service',
  description TEXT NOT NULL,
  qty INTEGER DEFAULT 1,
  price INTEGER DEFAULT 0,
  part_id INTEGER,
  warranty_months INTEGER DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  amount INTEGER NOT NULL,
  method TEXT DEFAULT 'cash',
  kind TEXT DEFAULT 'deposit',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  number TEXT NOT NULL UNIQUE,
  total INTEGER NOT NULL,
  discount INTEGER DEFAULT 0,
  paid INTEGER DEFAULT 0,
  remaining INTEGER DEFAULT 0,
  issued_at TEXT NOT NULL,
  pdf_path TEXT DEFAULT ''
);
CREATE TABLE IF NOT EXISTS warranties (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_item_id INTEGER NOT NULL REFERENCES ticket_items(id),
  invoice_id INTEGER,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS parts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  barcode TEXT DEFAULT '',
  buy_price INTEGER DEFAULT 0,
  sell_price INTEGER DEFAULT 0,
  qty INTEGER DEFAULT 0,
  min_qty INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER REFERENCES tickets(id),
  type TEXT NOT NULL DEFAULT 'delivery',
  remind_at TEXT NOT NULL,
  message TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS email_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  to_addr TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  attachment_path TEXT DEFAULT '',
  ics_content TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER DEFAULT 0,
  last_error TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  sent_at TEXT
);
CREATE TABLE IF NOT EXISTS license_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  fingerprint TEXT NOT NULL DEFAULT '',
  install_count INTEGER NOT NULL DEFAULT 1,
  first_run_at TEXT NOT NULL DEFAULT '',
  consented_at TEXT NOT NULL DEFAULT '',
  user_email TEXT NOT NULL DEFAULT '',
  buyer_name TEXT NOT NULL DEFAULT '',
  report_status TEXT NOT NULL DEFAULT 'pending',
  report_sent_at TEXT,
  last_report_error TEXT DEFAULT '',
  hardware_report TEXT DEFAULT ''
);
CREATE TABLE IF NOT EXISTS warranty_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER UNIQUE NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  months INTEGER NOT NULL DEFAULT 6,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,
  detail TEXT DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tickets_customer ON tickets(customer_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON reminders(status, remind_at);
CREATE INDEX IF NOT EXISTS idx_email_status ON email_queue(status);
''';

class Db {
  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'jsh_dashboard.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute(kSchema);
    _db = db;
    return db;
  }

  static Future<String> dbPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'jsh_dashboard.db');
  }

  /// بستن بانک برای بازیابی/جایگزینی فایل
  static Future<void> reset() async {
    final db = _db;
    _db = null;
    try {
      await db?.close();
    } catch (_) {}
  }

  /// پشتیبان دستی ساده به مسیر دلخواه (توسعه S-19 در فاز ۴)
  static Future<String> backupTo(String targetPath) async {
    final src = await dbPath();
    final srcFile = File(src);
    if (!await srcFile.exists()) throw Exception('بانک اطلاعاتی یافت نشد');
    await srcFile.copy(targetPath);
    return targetPath;
  }
}
