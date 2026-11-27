/// تشخیص: چرا tap روی سوییچ «مشتری جدید» عمل نمی‌کند
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/features/intake/intake.dart';

class _FakePP extends PathProviderPlatform {
  final String base;
  late final String supportPath = '$base/support';
  late final String docsPath = '$base/docs';
  _FakePP(this.base);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('jsh_diag');
    PathProviderPlatform.instance = _FakePP(tempDir.path);
    await Db.instance();
  });

  testWidgets('تشخیص سوییچ', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: IntakePage()),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    final sw = find.byType(Switch);
    print('DIAG switch count=${sw.evaluate().length}');
    final rect = tester.getRect(sw);
    print('DIAG rect=$rect center=${rect.center}');
    final hitAt = tester.hitTestOnBinding(rect.center);
    print('DIAG hit targets at center:');
    for (final h in hitAt.path.take(8)) {
      print('DIAG   -> ${h.target.runtimeType}');
    }
    await tester.tap(sw);
    await tester.pump(const Duration(milliseconds: 300));
    final value = tester.widget<Switch>(sw).value;
    print('DIAG after tap value=$value');
    print(
        'DIAG name field=${find.widgetWithText(TextField, 'نام و نام خانوادگی *').evaluate().length}');

    // روش دوم: drag/نوک زدن با موقعیت مطلق
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 300));
    print('DIAG after tapAt value=${tester.widget<Switch>(sw).value}');

    expect(true, isTrue);
  });
}
