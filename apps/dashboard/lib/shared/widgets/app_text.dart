/// متن برنامه — فرمان سراسری shrink-to-fit + فونت شخصی متن و فونت شخصی اعداد
/// با فعال بودن shrinkToFit در تنظیمات، هیچ متنی از کادر خود بیرون نمی‌زند
/// (ویندوز و موبایل) — حتی پس از تغییر فونت توسط کاربر.
library;

import 'package:flutter/material.dart';

import '../../core/theme/theme_config.dart';

/// متن عادی برنامه — فونت متن شخصی‌سازی‌شده + shrink اختیاری
class AppText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool softWrap;
  final int? maxLines;
  final bool shrinkOverride; // خالی = از تنظیمات سراسری

  const AppText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap = false,
    this.maxLines,
    this.shrinkOverride = true,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final base = (style ?? const TextStyle()).copyWith(
      color: style?.color,
    );
    final t = Text(text,
        style: base, textAlign: textAlign, maxLines: maxLines);
    if (cfg.shrinkToFit && shrinkOverride) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: t,
      );
    }
    return t;
  }
}

/// متن عددی — فونت اختصاصی اعداد کاربر (در کل برنامه یکسان اعمال می‌شود)
class AppNumText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool shrinkOverride;

  const AppNumText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.shrinkOverride = true,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final base = (style ?? const TextStyle())
        .copyWith(fontFamily: cfg.effectiveNumberFont);
    final t = Text(text, style: base, textAlign: textAlign);
    if (cfg.shrinkToFit && shrinkOverride) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: t,
      );
    }
    return t;
  }
}
