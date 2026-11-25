/// فیلد تاریخ شمسی — قاعده ۳ + قاعده ۱
/// نمایش فارسی، پاپ‌آپ تقویم، ورود دستی ۸ رقمی هوشمند (۱۴۰۵۰۹۰۴ → ۱۴۰۵/۰۹/۰۴)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils.dart';
import 'shamsi_calendar.dart';

/// فرمت هوشمند ورودی تاریخ: جداکننده خودکار بین سال/ماه/روز
String smartFormatDateInput(String raw) {
  final digits = toEnglishDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 4) return digits;
  if (digits.length <= 6) return '${digits.substring(0, 4)}/${digits.substring(4)}';
  return '${digits.substring(0, 4)}/${digits.substring(4, 6)}/${digits.substring(6, digits.length.clamp(6, 8))}';
}

/// پارس مقدار نمایشی فیلد (۱۴۰۵/۰۹/۰۴ یا ۱۴۰۵۰۹۰۴) به DateTime
DateTime? parseDateField(String display) {
  var s = toEnglishDigits(display.trim());
  if (RegExp(r'^\d{8}$').hasMatch(s)) {
    s = '${s.substring(0, 4)}/${s.substring(4, 6)}/${s.substring(6)}';
  }
  return parseShamsi(s);
}

class ShamsiDateField extends StatefulWidget {
  final String label;
  final DateTime? initial;
  final void Function(DateTime?) onChanged;
  final String? Function(String?)? validator;

  const ShamsiDateField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial,
    this.validator,
  });

  @override
  State<ShamsiDateField> createState() => _ShamsiDateFieldState();
}

class _ShamsiDateFieldState extends State<ShamsiDateField> {
  late final TextEditingController ctrl;
  bool userTyped = false;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController(
      text: widget.initial != null ? shamsiDate(widget.initial!) : '',
    );
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _emitIfValid() {
    final parsed = parseDateField(ctrl.text);
    widget.onChanged(parsed);
  }

  Future<void> _pick() async {
    final picked = await showShamsiDatePicker(
      context,
      initial: parseDateField(ctrl.text) ?? widget.initial,
    );
    if (picked != null) {
      ctrl.text = shamsiDate(picked);
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: '۱۴۰۵/۰۹/۰۴ یا ۱۴۰۵۰۹۰۴',
        helperText: 'انتخاب از تقویم یا ورود ۸ رقمی — جداکننده خودکار',
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_month),
          tooltip: 'تقویم شمسی',
          onPressed: _pick,
        ),
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹/]'))],
      onChanged: (v) {
        // فرمت هوشمند فقط در حالت تایپ پیوسته ۸ رقمی
        final digits = toEnglishDigits(v).replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 8 && !v.contains('/')) {
          ctrl.text = smartFormatDateInput(v);
          ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: ctrl.text.length),
          );
        }
        userTyped = true;
        _emitIfValid();
      },
      validator: widget.validator ??
          (v) {
            if (!userTyped && ctrl.text.isEmpty) return null;
            if (ctrl.text.isEmpty) return null;
            return parseDateField(ctrl.text) == null ? 'تاریخ نامعتبر است' : null;
          },
    );
  }
}
