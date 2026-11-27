/// فیلد عدد فارسی — قاعده ۱: نمایش فارسی، ذخیره انگلیسی
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils.dart';

/// نمایش فارسی while typing؛ مقدار انگلیسی با [numeric] یا [rawEnglish]
class PersianNumberField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool allowDecimal;
  /// جداسازی سه‌رقمی حین تایپ (بند ۱۹ نسخه ۳) — فقط برای فیلدهای مبلغ فعال شود
  final bool groupThousands;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;

  const PersianNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.allowDecimal = false,
    this.groupThousands = false,
    this.validator,
    this.onChanged,
    this.keyboardType,
  });

  @override
  State<PersianNumberField> createState() => _PersianNumberFieldState();
}

class _PersianNumberFieldState extends State<PersianNumberField> {
  @override
  void initState() {
    super.initState();
    // تبدیل مقدار اولیه انگلیسی به نمایش فارسی — در میکروتسک،
    // چون نوشتن در کنترلر حین build باعث خطای setState می‌شود
    final v = widget.controller.text;
    if (v.isNotEmpty) {
      scheduleMicrotask(() {
        final en = toEnglishDigits(v).replaceAll(',', '');
        widget.controller.text = widget.groupThousands
            ? toPersianDigits(_group(en))
            : toPersianDigits(en);
      });
    }
    widget.controller.addListener(_onCtrl);
  }

  void _onCtrl() {
    // تعویق میکروتسکی — تغییر مقدار کنترلر حین build/نوتیفیکیشن ممنوع است
    scheduleMicrotask(() {
      final v = widget.controller.text;
      final en = toEnglishDigits(v).replaceAll(',', '');
      String fa;
      if (widget.groupThousands && en.isNotEmpty) {
        // جداسازی سه‌رقمی مبلغ حین تایپ (بند ۱۹ نسخه ۳)
        final grouped = _group(en);
        fa = toPersianDigits(grouped);
      } else {
        fa = toPersianDigits(en);
      }
      if (v != fa) {
        widget.controller.value = TextEditingValue(
          text: fa,
          selection: TextSelection.collapsed(offset: fa.length),
        );
      }
    });
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remain = digits.length - i;
      b.write(digits[i]);
      if (remain > 1 && remain % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    super.dispose();
  }

  String get _rawEnglish => toEnglishDigits(widget.controller.text);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType ?? TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint != null ? toPersianDigits(widget.hint!) : null,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            RegExp(widget.allowDecimal ? r'[0-9۰-۹.,]' : r'[0-9۰-۹]')),
      ],
      onChanged: widget.onChanged == null
          ? null
          : (_) => widget.onChanged!(_rawEnglish),
    );
  }
}

/// مقدار عددی انگلیسی از فیلد (برای ذخیره در دیتابیس)
int englishIntOf(TextEditingController c) =>
    int.tryParse(toEnglishDigits(c.text).replaceAll(',', '')) ?? 0;

String englishRawOf(TextEditingController c) => toEnglishDigits(c.text);
