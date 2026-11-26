/// برنامه جانبی تولید کد فعال‌سازی J.S.H — فقط روی رایانه سازنده اجرا می‌شود
/// بند ۲ درخواست صاحب پروژه:
///   • با دادن شناسه دستگاه، کد فعال‌سازی می‌سازد (تاریخ اعتبار + سقف نصب توسط سازنده)
///   • گزارش همه کدهای صادرشده در بانک محلی: کد، خریدار، تاریخ صدور، اعتبار، نصب‌های گزارش‌شده
///   • خروجی CSV برای آرشیو
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:activation_core/activation_core.dart';

void main() {
  runApp(const GenApp());
}

class GenApp extends StatelessWidget {
  const GenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مولد کد فعال‌سازی J.S.H',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2563EB), useMaterial3: true),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(),
      ),
    );
  }
}

/// لایه بانک گزارش کدها
class CodeDb {
  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final db = await databaseFactory.openDatabase(
      p.join(dir.path, 'jsh_license_gen.db'),
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activation_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        device_short TEXT DEFAULT '',
        buyer TEXT DEFAULT '',
        expiry TEXT NOT NULL,
        max_reinstalls INTEGER DEFAULT 0,
        note TEXT DEFAULT '',
        installs_reported INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');
    _db = db;
    return db;
  }

  static Future<void> insertCode(Map<String, Object?> row) async {
    final db = await instance();
    await db.insert('activation_codes', row);
  }

  static Future<List<Map<String, Object?>>> all() async {
    final db = await instance();
    return db.query('activation_codes', orderBy: 'id DESC');
  }

  static Future<void> bumpInstalls(int id, int delta) async {
    final db = await instance();
    await db.rawUpdate(
        'UPDATE activation_codes SET installs_reported = installs_reported + ? WHERE id = ?',
        [delta, id]);
  }

  static Future<String> exportCsv(String dirPath) async {
    final rows = await all();
    final sb = StringBuffer()
      ..writeln('code,buyer,expiry,max_reinstalls,installs_reported,created_at,note');
    for (final r in rows) {
      String esc(Object? v) =>
          '"${(v ?? '').toString().replaceAll('"', '""')}"';
      sb.writeln([
        esc(r['code']),
        esc(r['buyer']),
        esc(r['expiry']),
        esc(r['max_reinstalls']),
        esc(r['installs_reported']),
        esc(r['created_at']),
        esc(r['note']),
      ].join(','));
    }
    final f = File(p.join(dirPath,
        'jsh_activation_codes_${DateTime.now().millisecondsSinceEpoch}.csv'));
    await f.writeAsString(sb.toString());
    return f.path;
  }
}

String toFa(String s) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(en[i], fa[i]);
  }
  return s;
}

String shamsi(DateTime dt) {
  final d = j.Jalali.fromDateTime(dt);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// پارس «۱۴۰۵/۰۹/۰۴» به میلادی
DateTime? parseShamsi(String input) {
  var s = input.trim();
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(fa[i], en[i]);
  }
  s = s.replaceAll(RegExp(r'[-٫]'), '/');
  final parts = s.split('/');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  final d = int.tryParse(parts[2].trim());
  if (y == null || m == null || d == null) return null;
  try {
    return j.Jalali(y, m, d).toDateTime();
  } catch (_) {
    return null;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  final deviceIdCtrl = TextEditingController();
  final buyerCtrl = TextEditingController();
  final expiryCtrl = TextEditingController(text: '');
  final reinstallsCtrl = TextEditingController(text: '0');
  final noteCtrl = TextEditingController();

  String? lastCode;
  String? lastError;
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await CodeDb.all();
    if (mounted) setState(() => rows = r);
  }

  /// اعتبار سریع شناسه دستگاه: ۳۲ کاراکتر هگز (با یا بدون خط تیره)
  String? _validateDeviceId(String raw) {
    final s = raw.replaceAll('-', '').trim().toLowerCase();
    if (s.length != 32) {
      return 'شناسه دستگاه باید ۳۲ کاراکتر باشد (همان که برنامه در صفحه فعال‌سازی نشان می‌دهد).';
    }
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(s)) {
      return 'شناسه دستگاه فقط باید رقم و حروف انگلیسی (hex) باشد.';
    }
    return null;
  }

  Future<void> _generate() async {
    setState(() {
      lastCode = null;
      lastError = null;
    });
    final devErr = _validateDeviceId(deviceIdCtrl.text);
    if (devErr != null) {
      setState(() => lastError = devErr);
      return;
    }
    final expiry = parseShamsi(expiryCtrl.text);
    if (expiry == null) {
      setState(() => lastError = 'تاریخ اعتبار را به شمسی وارد کنید؛ مثال: ۱۴۰۶/۰۹/۰۴');
      return;
    }
    final buyer = buyerCtrl.text.trim();
    if (buyer.isEmpty) {
      setState(() => lastError = 'نام خریدار را وارد کنید (برای گزارش کدها).');
      return;
    }
    final maxRe = int.tryParse(reinstallsCtrl.text.trim()) ?? 0;
    final device =
        deviceIdCtrl.text.replaceAll('-', '').trim().toLowerCase();
    final code = ActivationCodec.generate(
      expiry: DateTime.utc(expiry.year, expiry.month, expiry.day, 12),
      deviceId: device,
      maxReinstalls: maxRe.clamp(0, 255),
    );
    await CodeDb.insertCode({
      'code': code,
      'device_short': ActivationCodec.shortDeviceId(device),
      'buyer': buyer,
      'expiry': shamsi(expiry),
      'max_reinstalls': maxRe.clamp(0, 255),
      'note': noteCtrl.text.trim(),
      'installs_reported': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    setState(() {
      lastCode = code;
      _tabs.index = 0;
    });
    await _reload();
  }

  void _quickExpiry(int months) {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month + months, now.day);
    final jd = j.Jalali.fromDateTime(target);
    setState(() => expiryCtrl.text =
        '${jd.year}/${jd.month.toString().padLeft(2, '0')}/${jd.day.toString().padLeft(2, '0')}');
  }

  Future<void> _exportCsv() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final path = await CodeDb.exportCsv(docs.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خروجی CSV ذخیره شد:\n$path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطا در خروجی: $e')));
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    deviceIdCtrl.dispose();
    buyerCtrl.dispose();
    expiryCtrl.dispose();
    reinstallsCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مولد کد فعال‌سازی J.S.H — فقط سازنده'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'تولید کد'),
            Tab(text: 'تاریخچه کدها'),
            Tab(text: 'راهنما'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _generateTab(),
          _historyTab(),
          _helpTab(),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _generateTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _field(deviceIdCtrl, 'شناسه دستگاه (۳۲ کاراکتر — کپی‌شده از صفحه فعال‌سازی برنامه)',
            hint: 'مثال: 8f3b1c2d-4e5f-6a7b-8c9d-0e1f2a3b4c5d (بدون خط تیره هم قابل استفاده است)'),
        _field(buyerCtrl, 'نام خریدار', hint: 'مثال: موبایل رضایی'),
        _field(expiryCtrl, 'تاریخ پایان اعتبار (شمسی)', hint: '۱۴۰۶/۰۹/۰۴'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in [1, 3, 6, 12, 24])
              OutlinedButton(
                  onPressed: () => _quickExpiry(m),
                  child: Text(toFa(m >= 12
                      ? '${m ~/ 12} سال'
                      : '$m ماه'))),
          ],
        ),
        const SizedBox(height: 10),
        _field(reinstallsCtrl, 'سقف نصب مجدد روی همان دستگاه (۰ = پیش‌فرض ۳ بار)'),
        _field(noteCtrl, 'یادداشت (اختیاری)', hint: 'مثال: خرید یک‌ساله نسخه کامل'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.vpn_key_rounded),
          label: const Text('تولید کد فعال‌سازی'),
        ),
        if (lastError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Text(lastError!, style: const TextStyle(fontSize: 13)),
          ),
        ],
        if (lastCode != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('کد فعال‌سازی ساخته شد و در تاریخچه ثبت شد:',
                    style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                SelectableText(lastCode!,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: lastCode!));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('کد کپی شد — برای خریدار بفرستید')));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('کپی کد'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _historyTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('تعداد کدها: ${toFa('${rows.length}')}',
                style: const TextStyle(fontSize: 13)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _exportCsv,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('خروجی CSV'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('به‌روزرسانی'),
            ),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('هنوز کدی تولید نشده است'))
                : SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 18,
                      headingTextStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                      dataTextStyle: const TextStyle(fontSize: 11.5),
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('کد فعال‌سازی')),
                        DataColumn(label: Text('خریدار')),
                        DataColumn(label: Text('انقضا')),
                        DataColumn(label: Text('سقف نصب')),
                        DataColumn(label: Text('نصب گزارش‌شده')),
                        DataColumn(label: Text('ثبت نصب')),
                      ],
                      rows: [
                        for (final r in rows)
                          DataRow(cells: [
                            DataCell(Text(toFa('${r['id']}'))),
                            DataCell(SelectableText('${r['code']}')),
                            DataCell(Text('${r['buyer']}')),
                            DataCell(Text(toFa('${r['expiry']}'))),
                            DataCell(Text((r['max_reinstalls'] as int? ?? 0) == 0
                                ? 'پیش‌فرض'
                                : toFa('${r['max_reinstalls']}'))),
                            DataCell(
                                Text(toFa('${r['installs_reported']}'))),
                            DataCell(IconButton(
                              tooltip: 'خریدار نصب را گزارش کرده است — +۱',
                              icon: const Icon(Icons.add_task, size: 19),
                              onPressed: () async {
                                await CodeDb.bumpInstalls(r['id'] as int, 1);
                                await _reload();
                              },
                            )),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _helpTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('راهنمای فعال‌سازی خریدار', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Text(
          '۱) خریدار برنامه را نصب و ویزارد راه‌اندازی را کامل می‌کند.\n'
          '۲) برنامه صفحه «فعال‌سازی» را نشان می‌دهد؛ شناسه ۳۲ کاراکتری دستگاه را با دکمه «کپی شناسه دستگاه» کپی می‌کند و برای شما می‌فرستد (واتساپ/پیامک).\n'
          '۳) شما اینجا شناسه را وارد، تاریخ اعتبار و سقف نصب را تعیین و کد می‌سازید.\n'
          '۴) کد را برای خریدار می‌فرستید؛ او در صفحه فعال‌سازی وارد می‌کند و برنامه اجرا می‌شود.\n'
          '۵) برای خرید چند سیستم، برای هر شناسه یک کد جدا می‌سازید — همه با نام همان خریدار در تاریخچه ثبت می‌شوند.\n'
          '۶) با «ثبت نصب» در تاریخچه، نصب‌های گزارش‌شده هر کد را شمارش می‌کنید.\n\n'
          'امنیت:\n'
          '• کد فقط روی همان دستگاه کار می‌کند (اتصال به مادربورد + CPU).\n'
          '• عقب‌بردن تاریخ سیستم، اعتبار را طولانی نمی‌کند (نگهبان تاریخ).\n'
          '• پس از پایان اعتبار، برنامه با پیام تمدید قفل می‌شود.',
          style: TextStyle(fontSize: 13.5, height: 2),
        ),
      ],
    );
  }
}

