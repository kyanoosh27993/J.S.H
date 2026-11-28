import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/mobile_link_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String base;
  late final String supportPath = '$base/support';
  late final String docsPath = '$base/docs';
  _FakePathProvider(this.base);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

/// v0.12.4 — تست سرور اتصال موبایل: جفت‌سازی، توکن، جستجوی سفارش و آپلود اتچ
void main() {
  // بدون TestWidgetsFlutterBinding — به HTTP واقعی روی localhost نیاز داریم
  // (binding تست، HttpClient را رهگیری و همه پاسخ‌ها را 400 می‌کند)
  late Directory tempDir;
  late int port;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_mobile_link');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Db.instance();
    await MobileLinkService.start(port: 0);
    port = MobileLinkService.state.value.port;
  });

  tearDownAll(() async {
    await MobileLinkService.stop();
    await Db.reset();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  late String token;

  test('جفت‌سازی با کد اشتباه رد می‌شود', () async {
    final hc = HttpClient();
    final req = await hc.post('127.0.0.1', port, '/api/pair');
    req.headers.contentType = ContentType.json;
    req.write('{"pcCode":"000000","deviceName":"تست"}');
    final res = await req.close();
    expect(res.statusCode, 401);
    await res.drain();
  });

  test('جفت‌سازی درست → توکن صادر می‌شود', () async {
    final code = MobileLinkService.state.value.pairingCode;
    expect(code, isNotEmpty);
    final hc = HttpClient();
    final req = await hc.post('127.0.0.1', port, '/api/pair');
    req.headers.contentType = ContentType.json;
    req.write('{"pcCode":"$code","deviceName":"گوشی تست"}');
    final res = await req.close();
    expect(res.statusCode, 200);
    final body = await res.transform(utf8.decoder).join();
    token = (jsonDecode(body) as Map)['token'] as String;
    expect(token, isNotEmpty);
    expect(MobileLinkService.state.value.devices, contains('گوشی تست'));
  });

  test('verify با توکن پاسخ می‌دهد — مسیر بدون توکن 401', () async {
    final hc = HttpClient();
    var req = await hc.get('127.0.0.1', port, '/api/verify');
    var res = await req.close();
    expect(res.statusCode, 401);
    await res.drain();
    req = await hc.get('127.0.0.1', port, '/api/verify?token=$token');
    res = await req.close();
    expect(res.statusCode, 200);
    await res.drain();
  });

  test('اسکن/جستجوی سفارش روی PC', () async {
    // مشتری + دستگاه + سفارش واقعی
    final custId = await CustomerRepo
        .insert(Customer(name: 'موبایل‌کار', phone: '09130000000'));
    final devId = await DeviceRepo.insert(Device(
        customerId: custId, model: 'iPhone 15', category: 'موبایل'));
    final ticket = Ticket(
        code: 'RCP-MOB-TEST',
        customerId: custId,
        deviceId: devId,
        intakeDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 1)),
        dueTime: '10:00',
        defect: 'تست',
        diagnosis: '',
        phoneState: '',
        estimateAmount: 0,
        depositAmount: 0,
        status: 'intake',
        accessories: const [],
        termsAccepted: true,
        signaturePath: '');
    await TicketRepo.insert(ticket);

    final hc = HttpClient();
    final req = await hc.get(
        '127.0.0.1', port, '/api/scan?token=$token&q=RCP-MOB-TEST');
    final res = await req.close();
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, Object?>;
    final results = (body['results']! as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    expect(results, isNotEmpty);
    expect(results.first['code'], 'RCP-MOB-TEST');
    expect(results.first['model'], 'iPhone 15');
  });

  test('آپلود عکس از گوشی → ردیف attachments ساخته می‌شود', () async {
    final tickets = await TicketRepo.all();
    final tid = tickets.first.id!;
    final bytes =
        List.generate(512, (i) => (i * 7) % 256); // فایل آزمایشی غیرخالی
    final hc = HttpClient();
    final req = await hc.post('127.0.0.1', port,
        '/api/attach?token=$token&ticket=$tid&note=تست%20گوشی');
    req.headers.set('x-filename', 'mob_test.jpg');
    req.headers.contentLength = bytes.length;
    req.add(bytes);
    final res = await req.close();
    expect(res.statusCode, 200);
    final body =
        jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    expect(body['ok'], true);
    final path = body['path'] as String;
    expect(File(path).existsSync(), true);
    expect(File(path).lengthSync(), 512);
    final db = await Db.instance();
    final rows = await db.query('attachments',
        where: 'ticket_id = ?', whereArgs: [tid]);
    expect(rows.map((r) => r['path']), contains(path));
    expect(rows.first['note'], 'تست گوشی');
  });
}
