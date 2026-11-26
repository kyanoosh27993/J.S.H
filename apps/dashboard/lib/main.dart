import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/app_session.dart';
import 'core/services/font_service.dart';
import 'core/theme/theme_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = AppSession.I;
  // مقاوم‌سازی: حتی اگر راه‌اندازی اولیه خطا داد، UI بالا می‌آید تا کاربر
  // همیشه چیزی ببیند (نه صفحه سیاه) و پیام خطا نمایش داده شود
  Object? bootError;
  try {
    await session.init();
  } catch (e) {
    bootError = e;
  }
  try {
    // شخصی‌سازی: بارگذاری پیکربندی تم و فونت‌های انتخابی کاربر
    await ThemeConfig.load();
    final cfg = ThemeConfig.notifier.value;
    if (cfg.textFontPath.isNotEmpty) {
      await FontService.loadDynamicFont(cfg.textFontFamily, cfg.textFontPath);
    }
    if (cfg.numberFontPath.isNotEmpty) {
      await FontService.loadDynamicFont(cfg.numberFontFamily, cfg.numberFontPath);
    }
  } catch (_) {}
  runApp(JshDashboardApp(session: session, bootError: bootError));
}
