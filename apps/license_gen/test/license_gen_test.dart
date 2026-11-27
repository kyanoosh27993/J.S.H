/// تست دود برنامه مولد — UI بالا می‌آید و تب‌ها موجودند
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'dart:io';

import 'package:jsh_license_gen/main.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String base;
  _FakePathProvider(this.base);
  @override
  Future<String?> getApplicationSupportPath() async => '$base/support';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$base/docs';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final t = await Directory.systemTemp.createTemp('gen_test');
    PathProviderPlatform.instance = _FakePathProvider(t.path);
  });

  testWidgets('برنامه بالا می‌آید و سه تب دارد', (tester) async {
    await tester.pumpWidget(const GenApp());
    await tester.pumpAndSettle();
    expect(find.text('تولید کد'), findsOneWidget);
    expect(find.text('تاریخچه کدها'), findsOneWidget);
    expect(find.text('راهنما'), findsOneWidget);
    expect(find.text('تولید کد فعال‌سازی'), findsOneWidget);
  });
}
