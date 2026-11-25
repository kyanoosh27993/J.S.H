/// سرویس فونت سیستم — قاعده شخصی‌سازی
/// کاربر فونت متن و فونت اعداد را از فونت‌های نصب‌شده ویندوز انتخاب می‌کند؛
/// فونت انتخابی با FontLoader در زمان اجرا بارگذاری و در کل برنامه و تم اعمال می‌شود.
library;

import 'dart:io';

import 'package:flutter/services.dart';

class FontService {
  static const _defaultFamily = 'Vazirmatn';

  /// پوشه‌های فونت سیستم بر اساس پلتفرم
  static List<String> _fontDirs() {
    if (Platform.isWindows) {
      return [r'C:\Windows\Fonts', r'C:\Windows\System32\spool\drivers\color'];
    }
    if (Platform.isLinux) {
      return [
        '/usr/share/fonts',
        '/usr/local/share/fonts',
        '${Platform.environment['HOME'] ?? ''}/.local/share/fonts',
        '${Platform.environment['HOME'] ?? ''}/.fonts',
      ];
    }
    if (Platform.isMacOS) {
      return ['/System/Library/Fonts', '/Library/Fonts'];
    }
    return [];
  }

  /// نام خانواده تمیزشده از نام فایل — Vazirmatn-Bold.ttf → Vazirmatn
  static String cleanFamilyName(String fileName) {
    var n = fileName
        .replaceAll(RegExp(r'\.(ttf|otf|TTF|OTF)$'), '')
        .replaceAll(RegExp(r'-(Regular|Bold|Light|Medium|SemiBold|Thin|Black|ExtraBold|ExtraLight|Italic)$'), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
    if (n.length > 32) n = n.substring(0, 32);
    return n.isEmpty ? 'UserFont' : n;
  }

  /// فهرست فونت‌های قابل انتخاب: وزیرمتن برنامه + فونت‌های نصب‌شده سیستم
  static Future<List<String>> listSystemFonts() async {
    final out = <String>{_defaultFamily};
    for (final dirPath in _fontDirs()) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is! File) continue;
          final p = f.path.toLowerCase();
          if (p.endsWith('.ttf') || p.endsWith('.otf')) {
            out.add(cleanFamilyName(f.path.split(Platform.pathSeparator).last));
          }
        }
      } catch (_) {}
    }
    final list = out.toList()..sort();
    return list;
  }

  /// یافتن مسیر فایل فونت برای نام خانواده (اولین تفاوت Regular ترجیح دارد)
  static Future<String?> findFontFile(String family) async {
    if (family == _defaultFamily) return null; // دارایی داخلی برنامه
    final candidates = <String>[];
    for (final dirPath in _fontDirs()) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is! File) continue;
          final p = f.path.toLowerCase();
          if (!p.endsWith('.ttf') && !p.endsWith('.otf')) continue;
          if (cleanFamilyName(f.path.split(Platform.pathSeparator).last) ==
              family) {
            candidates.add(f.path);
          }
        }
      } catch (_) {}
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      bool regular(String s) =>
          s.toLowerCase().contains('regular') ||
          (!s.toLowerCase().contains(RegExp(r'bold|italic|light|thin|black')));
      return regular(b) == regular(a) ? 0 : (regular(b) ? 1 : -1);
    });
    return candidates.first;
  }

  /// بارگذاری پویا فونت در زمان اجرا — پس از آن family در تم قابل استفاده است
  static Future<bool> loadDynamicFont(String family, String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return false;
      final bytes = await f.readAsBytes();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return true;
    } catch (_) {
      return false;
    }
  }
}
