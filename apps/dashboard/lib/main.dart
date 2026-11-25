import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/app_session.dart';
import 'core/services/font_service.dart';
import 'core/theme/theme_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = AppSession.I;
  await session.init();
  // شخصی‌سازی: بارگذاری پیکربندی تم و فونت‌های انتخابی کاربر از ویندوز
  await ThemeConfig.load();
  final cfg = ThemeConfig.notifier.value;
  if (cfg.textFontPath.isNotEmpty) {
    await FontService.loadDynamicFont(cfg.textFontFamily, cfg.textFontPath);
  }
  if (cfg.numberFontPath.isNotEmpty) {
    await FontService.loadDynamicFont(cfg.numberFontFamily, cfg.numberFontPath);
  }
  runApp(JshDashboardApp(session: session));
}
