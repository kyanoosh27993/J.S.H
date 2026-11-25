/// فیلد عدد فارسی — قاعده ۱: نمایش فارسی، ذخیره انگلیسی
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils.dart';

/// نمایش فارسی while typing؛ مقدار انگلیسی با [numeric] یا [rawEnglish]
class PersianNumberField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool allowDecimal;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;

  const PersianNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.allowDecimal = false,
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
    // تبدیل مقدار اولیه انگلیسی به نمایش فارسی
    if (widget.controller.text.isNotEmpty) {
      final v = widget.controller.text;
      widget.controller.text = toPersianDigits(toEnglishDigits(v));
    }
    widget.controller.addListener(_onCtrl);
  }

  void _onCtrl() {
    final v = widget.controller.text;
    final en = toEnglishDigits(v);
    final fa = toPersianDigits(en);
    if (v != fa) {
      widget.controller.value = TextEditingValue(
        text: fa,
        selection: TextSelection.collapsed(offset: fa.length),
      );
    }
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
