/// موتور تم مدرن — سه پیش‌فرض (تیره، روشن، کرمی‌طلایی) + شخصی‌سازی ریز کاربر
/// پایدارسازی در جدول settings (کلید theme_config) — بازطراحی کامل نسخه ۰.۳
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../repos.dart';

/// پیش‌فرض‌های تم
enum ThemePreset { dark, light, creamGold }

extension ThemePresetX on ThemePreset {
  String get key => switch (this) {
        ThemePreset.dark => 'dark',
        ThemePreset.light => 'light',
        ThemePreset.creamGold => 'creamGold',
      };
  String get labelFa => switch (this) {
        ThemePreset.dark => 'تیره مدرن',
        ThemePreset.light => 'روشن کلاسیک',
        ThemePreset.creamGold => 'کرمی طلایی',
      };
  static ThemePreset fromKey(String k) => switch (k) {
        'light' => ThemePreset.light,
        'creamGold' => ThemePreset.creamGold,
        _ => ThemePreset.dark,
      };
}

/// پالت هر پیش‌فرض — همه رنگ‌های پوسته از اینجا می‌آیند تا شخصی‌سازی کامل باشد
class ThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final List<Color> chartColors;
  final List<Color> sidebarGradient;
  final Brightness brightness;

  const ThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.chartColors,
    required this.sidebarGradient,
    required this.brightness,
  });
}

const kPalettes = <ThemePreset, ThemePalette>{
  ThemePreset.dark: ThemePalette(
    background: Color(0xFF0B1020),
    surface: Color(0xFF121A2B),
    surfaceAlt: Color(0xFF18233B),
    border: Color(0xFF223049),
    textPrimary: Color(0xFFE8EEF9),
    textSecondary: Color(0xFF93A3BC),
    primary: Color(0xFF4F8CFF),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF22D3EE),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    chartColors: [
      Color(0xFF4F8CFF), Color(0xFF22D3EE), Color(0xFFA78BFA),
      Color(0xFF34D399), Color(0xFFFBBF24), Color(0xFFF87171),
      Color(0xFFF472B6),
    ],
    sidebarGradient: [Color(0xFF0B1020), Color(0xFF101A31)],
    brightness: Brightness.dark,
  ),
  ThemePreset.light: ThemePalette(
    background: Color(0xFFF3F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF8FAFF),
    border: Color(0xFFE1E8F2),
    textPrimary: Color(0xFF1B2A41),
    textSecondary: Color(0xFF5A6B85),
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF0EA5E9),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    chartColors: [
      Color(0xFF2563EB), Color(0xFF0EA5E9), Color(0xFF8B5CF6),
      Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
      Color(0xFFEC4899),
    ],
    sidebarGradient: [Color(0xFFFFFFFF), Color(0xFFF3F6FB)],
    brightness: Brightness.light,
  ),
  ThemePreset.creamGold: ThemePalette(
    background: Color(0xFFF6EFE0),
    surface: Color(0xFFFFFAF0),
    surfaceAlt: Color(0xFFFBF4E4),
    border: Color(0xFFE8DBC0),
    textPrimary: Color(0xFF3E2F1C),
    textSecondary: Color(0xFF8A7455),
    primary: Color(0xFFA8761F),
    onPrimary: Color(0xFFFFF8E7),
    accent: Color(0xFFD4A437),
    success: Color(0xFF6B8E23),
    warning: Color(0xFFC77B3F),
    danger: Color(0xFFB22222),
    chartColors: [
      Color(0xFFA8761F), Color(0xFFD4A437), Color(0xFF6B8E23),
      Color(0xFF8B4513), Color(0xFFC77B3F), Color(0xFF5F7A61),
      Color(0xFFB22222),
    ],
    sidebarGradient: [Color(0xFFFFFAF0), Color(0xFFF6EFE0)],
    brightness: Brightness.light,
  ),
};

/// پیکربندی شخصی‌سازی — هر جزء با ریز جزئیات قابل تغییر است
class ThemeConfig {
  String preset; // کلید پیش‌فرض
  String accentHex; // رنگ تاکیدی شخصی (خالی = پیش‌فرض تم)
  double radiusScale; // 0.6 .. 2.0 — گردی گوشه‌ها
  double fontScale; // 0.85 .. 1.35 — اندازه متن
  double density; // 0.85 .. 1.5 — ارتفاع سطرها و چگالی
  String textFontFamily; // '' = وزیرمتن پیش‌فرض برنامه
  String textFontPath; // مسیر فایل فونت انتخابی ویندوز
  String numberFontFamily; // فونت نمایش اعداد در کل برنامه
  String numberFontPath;
  bool shrinkToFit; // فرمان سراسری: همه متن‌ها داخل کادر بمانند
  bool animations; // انیمیشن‌های hover و ترنزیشن‌ها
  bool showChartsOnDashboard;

  ThemeConfig({
    this.preset = 'dark',
    this.accentHex = '',
    this.radiusScale = 1.0,
    this.fontScale = 1.0,
    this.density = 1.0,
    this.textFontFamily = '',
    this.textFontPath = '',
    this.numberFontFamily = '',
    this.numberFontPath = '',
    this.shrinkToFit = true,
    this.animations = true,
    this.showChartsOnDashboard = true,
  });

  ThemePreset get presetEnum => ThemePresetX.fromKey(preset);
  ThemePalette get palette {
    final p = kPalettes[presetEnum]!;
    final hex = accentHex;
    if (hex.isNotEmpty && hex.length >= 6) {
      final v = int.tryParse('FF$hex', radix: 16);
      if (v != null) {
        return _withAccent(p, Color(v));
      }
    }
    return p;
  }

  /// اعمال رنگ تاکیدی شخصی روی پالت
  ThemePalette _withAccent(ThemePalette p, Color accent) => ThemePalette(
        background: p.background,
        surface: p.surface,
        surfaceAlt: p.surfaceAlt,
        border: p.border,
        textPrimary: p.textPrimary,
        textSecondary: p.textSecondary,
        primary: accent,
        onPrimary: p.brightness == Brightness.dark
            ? Colors.white
            : Colors.white,
        accent: accent,
        success: p.success,
        warning: p.warning,
        danger: p.danger,
        chartColors: [accent, ...p.chartColors.take(6)],
        sidebarGradient: p.sidebarGradient,
        brightness: p.brightness,
      );

  double get baseRadius => 14 * radiusScale;

  String get effectiveTextFont =>
      textFontFamily.isEmpty ? 'Vazirmatn' : textFontFamily;
  String get effectiveNumberFont =>
      numberFontFamily.isEmpty ? effectiveTextFont : numberFontFamily;

  Map<String, dynamic> toJson() => {
        'preset': preset,
        'accentHex': accentHex,
        'radiusScale': radiusScale,
        'fontScale': fontScale,
        'density': density,
        'textFontFamily': textFontFamily,
        'textFontPath': textFontPath,
        'numberFontFamily': numberFontFamily,
        'numberFontPath': numberFontPath,
        'shrinkToFit': shrinkToFit,
        'animations': animations,
        'showChartsOnDashboard': showChartsOnDashboard,
      };

  factory ThemeConfig.fromJson(Map<String, dynamic> j) => ThemeConfig(
        preset: (j['preset'] ?? 'dark') as String,
        accentHex: (j['accentHex'] ?? '') as String,
        radiusScale: (j['radiusScale'] ?? 1.0) as double,
        fontScale: (j['fontScale'] ?? 1.0) as double,
        density: (j['density'] ?? 1.0) as double,
        textFontFamily: (j['textFontFamily'] ?? '') as String,
        textFontPath: (j['textFontPath'] ?? '') as String,
        numberFontFamily: (j['numberFontFamily'] ?? '') as String,
        numberFontPath: (j['numberFontPath'] ?? '') as String,
        shrinkToFit: (j['shrinkToFit'] ?? true) as bool,
        animations: (j['animations'] ?? true) as bool,
        showChartsOnDashboard: (j['showChartsOnDashboard'] ?? true) as bool,
      );

  ThemeConfig copyWith({
    String? preset,
    String? accentHex,
    double? radiusScale,
    double? fontScale,
    double? density,
    String? textFontFamily,
    String? textFontPath,
    String? numberFontFamily,
    String? numberFontPath,
    bool? shrinkToFit,
    bool? animations,
    bool? showChartsOnDashboard,
  }) =>
      ThemeConfig(
        preset: preset ?? this.preset,
        accentHex: accentHex ?? this.accentHex,
        radiusScale: radiusScale ?? this.radiusScale,
        fontScale: fontScale ?? this.fontScale,
        density: density ?? this.density,
        textFontFamily: textFontFamily ?? this.textFontFamily,
        textFontPath: textFontPath ?? this.textFontPath,
        numberFontFamily: numberFontFamily ?? this.numberFontFamily,
        numberFontPath: numberFontPath ?? this.numberFontPath,
        shrinkToFit: shrinkToFit ?? this.shrinkToFit,
        animations: animations ?? this.animations,
        showChartsOnDashboard: showChartsOnDashboard ?? this.showChartsOnDashboard,
      );

  // ── پایدارسازی ──
  static const _key = 'theme_config';
  static final ValueNotifier<ThemeConfig> notifier =
      ValueNotifier<ThemeConfig>(ThemeConfig());

  static Future<void> load() async {
    try {
      final raw = await SettingsRepo.get(_key);
      if (raw.isNotEmpty) {
        notifier.value = ThemeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  static Future<void> save(ThemeConfig c) async {
    notifier.value = c;
    try {
      await SettingsRepo.set(_key, jsonEncode(c.toJson()));
    } catch (_) {}
  }
}

/// دسترسی سراسری به پیکربندی تم داخل ویجت‌ها
class AppThemeScope extends InheritedNotifier<ValueNotifier<ThemeConfig>> {
  const AppThemeScope({super.key, required super.notifier, required super.child});

  static ThemeConfig of(BuildContext context) {
    final s =
        context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return s?.notifier?.value ?? ThemeConfig.notifier.value;
  }
}

class AppTheme {
  /// ساخت ThemeData کامل از پیکربندی — مدرن، گرد، سایه‌دار
  static ThemeData build(ThemeConfig cfg) {
    final p = cfg.palette;
    final r = cfg.baseRadius;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.accent,
      onSecondary: p.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      error: p.danger,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceAlt,
      outline: p.border,
      outlineVariant: p.border,
    );

    final baseText = ThemeData(
      fontFamily: cfg.effectiveTextFont,
      colorScheme: scheme,
      useMaterial3: true,
    ).textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      fontFamily: cfg.effectiveTextFont,
      textTheme: baseText.apply(
        fontSizeFactor: cfg.fontScale,
        fontFamily: cfg.effectiveTextFont,
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 2,
        shadowColor: p.brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
          side: BorderSide(color: p.border, width: 0.7),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface.withValues(alpha: 0.92),
        foregroundColor: p.textPrimary,
        elevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: p.border, width: 0.7)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        hintStyle: TextStyle(color: p.textSecondary.withValues(alpha: 0.8)),
        labelStyle: TextStyle(color: p.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.8),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.8),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r * 0.8),
          borderSide: BorderSide(color: p.primary, width: 1.6),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(r * 0.8))),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: p.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r * 0.8),
          side: BorderSide(color: p.border, width: 0.7),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        side: BorderSide(color: p.border, width: 0.7),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r)),
        labelStyle: TextStyle(color: p.textPrimary, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(r * 0.8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          side: BorderSide(color: p.primary.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(r * 0.8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.primary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 1.2)),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 0.7, space: 1),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.primary.withValues(alpha: 0.45)),
        radius: const Radius.circular(8),
        thickness: WidgetStatePropertyAll(6.0),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceAlt,
        contentTextStyle: TextStyle(color: p.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r * 0.8)),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        titleTextStyle: TextStyle(
            color: p.textPrimary,
            fontSize: 13.5 * cfg.fontScale,
            fontWeight: FontWeight.w600),
        subtitleTextStyle: TextStyle(
            color: p.textSecondary, fontSize: 12 * cfg.fontScale),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.border),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.primary : null),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        textStyle: TextStyle(color: p.textPrimary, fontSize: 11.5),
      ),
    );
  }
}
