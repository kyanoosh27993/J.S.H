import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// گارد هم‌گامی نسخه — pubspec.yaml و نصب‌کننده Inno و AppInfo.version
/// باید همیشه یک شماره باشند تا فایل‌های خروجی ناهمگام نشوند (v0.12.3).
void main() {
  test('نسخه در pubspec، نصب‌کننده و AppInfo هم‌گام است', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m1 = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(m1, isNotNull, reason: 'نسخه در pubspec.yaml یافت نشد');
    final pub = m1!.group(1)!;

    final iss = File('../installer/jsh_dashboard.iss').readAsStringSync();
    final m2 = RegExp(r'#define MyAppVersion "(\d+\.\d+\.\d+)"').firstMatch(iss);
    expect(m2, isNotNull, reason: 'MyAppVersion در نصب‌کننده یافت نشد');
    final issVer = m2!.group(1)!;

    final constants =
        File('lib/core/constants.dart').readAsStringSync();
    final m3 = RegExp(r"String version = '(\d+\.\d+\.\d+)'")
        .firstMatch(constants);
    expect(m3, isNotNull, reason: 'AppInfo.version یافت نشد');
    final dartVer = m3!.group(1)!;

    expect(pub, issVer,
        reason: 'pubspec.yaml ($pub) و نصب‌کننده ($issVer) هم‌گام نیستند');
    expect(pub, dartVer,
        reason: 'pubspec.yaml ($pub) و AppInfo.version ($dartVer) هم‌گام نیستند');
  });
}
