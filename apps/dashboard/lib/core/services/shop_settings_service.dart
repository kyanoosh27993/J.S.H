/// سرویس تنظیمات فروشگاهی — فاز ۴ (بندهای ۱، ۶، ۱۸)
/// - لوازم همراه قابل ویرایش در تنظیمات و استفاده در پذیرش (بند ۱۰)
/// - فایل‌های امضا/مهر/لوگو فروشگاه با file_selector (بند ۶) — ویندوز و اندروید
/// - تصاویر در پوشه اسناد برنامه کپی می‌شوند تا مسیرشان پایدار بماند
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../repos.dart';

/// کلیدهای تصاویر فروشگاه
enum ShopImage { signature, stamp, logo }

extension ShopImageKey on ShopImage {
  String get settingKey => switch (this) {
        ShopImage.signature => 'img_signature',
        ShopImage.stamp => 'img_stamp',
        ShopImage.logo => 'img_logo',
      };
  String get labelFa => switch (this) {
        ShopImage.signature => 'امضا',
        ShopImage.stamp => 'مهر',
        ShopImage.logo => 'لوگو',
      };
}

class ShopSettingsService {
  // ── لوازم همراه — قابل ویرایش (بند ۱۰) ──
  static const String accessoriesKey = 'accessories_list';

  static Future<List<String>> loadAccessories() async {
    final raw = await SettingsRepo.get(accessoriesKey);
    if (raw.trim().isEmpty) return List<String>.from(Accessory.all);
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.where((e) => e.trim().isNotEmpty).toList();
    } catch (_) {
      return List<String>.from(Accessory.all);
    }
  }

  static Future<void> saveAccessories(List<String> items) async {
    await SettingsRepo.set(
        accessoriesKey, jsonEncode(items.map((e) => e.trim()).toList()));
  }

  // ── تصاویر امضا/مهر/لوگو (بند ۶ + ۱۸) ──
  static Future<String> _imagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = p.join(docs.path, 'JSH_images');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// انتخاب تصویر و کپی در پوشه برنامه — خروجی: پیام خطا یا null
  static Future<String?> pickAndSave(ShopImage kind) async {
    const typeGroup = XTypeGroup(
      label: 'تصویر',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return null; // کاربر انصراف داد
    final ext = p.extension(file.path).toLowerCase();
    final fixedExt = (ext == '.jpg' || ext == '.jpeg') ? '.jpg' : '.png';
    final dir = await _imagesDir();
    final target = p.join(dir, '${kind.settingKey}$fixedExt');
    // پاک‌سازی نسخه‌های قبلی با پسوند دیگر
    for (final old in ['.png', '.jpg']) {
      if (old == fixedExt) continue;
      try {
        final f = File(p.join(dir, '${kind.settingKey}$old'));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    try {
      await File(file.path).copy(target);
    } catch (e) {
      return 'کپی تصویر ناموفق بود: $e';
    }
    await SettingsRepo.set(kind.settingKey, target);
    return null;
  }

  /// پاک کردن تصویر انتخابی
  static Future<void> clear(ShopImage kind) async {
    final path = await SettingsRepo.get(kind.settingKey);
    if (path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await SettingsRepo.set(kind.settingKey, '');
  }

  /// مسیر فعلی تصویر (خالی یعنی ثبت نشده)
  static Future<String> pathOf(ShopImage kind) =>
      SettingsRepo.get(kind.settingKey);

  /// بایت‌های تصویر — فقط PNG/JPEG معتبر؛ برای PDF
  static Future<List<int>?> bytesOf(ShopImage kind) async {
    final path = await pathOf(kind);
    if (path.isEmpty) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      if (bytes.length < 8) return null;
      final isPng =
          bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
      if (!isPng && !isJpeg) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
