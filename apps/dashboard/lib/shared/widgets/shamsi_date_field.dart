/// فیلد تاریخ شمسی — قاعده ۳ + قاعده ۱
/// نمایش فارسی، پاپ‌آپ تقویم، ورود دستی ۸ رقمی هوشمند (۱۴۰۵۰۹۰۴ → ۱۴۰۵/۰۹/۰۴)
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';

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
  /// کنترلر بیرونی — فرم می‌تواند هنگام reset آن را پاک کند
  final TextEditingController? controller;

  const ShamsiDateField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial,
    this.validator,
    this.controller,
  });

  @override
  State<ShamsiDateField> createState() => _ShamsiDateFieldState();
}

class _ShamsiDateFieldState extends State<ShamsiDateField> {
  late final TextEditingController ctrl;
  bool userTyped = false;
  bool _formatting = false;

  @override
  void initState() {
    super.initState();
    ctrl = widget.controller ??
        TextEditingController(
          text: widget.initial != null ? shamsiDate(widget.initial!) : '',
        );
    // قاعده فاز ۳: هر تغییر متن (تایپ/پیست/برنامه‌ای) باید به والد منتشر شود
    ctrl.addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() {
    if (_formatting) return;
    _emitIfValid();
  }

  @override
  void dispose() {
    ctrl.removeListener(_onCtrlChanged);
    if (widget.controller == null) {
      ctrl.dispose(); // فقط کنترلر متعلق به خود فیلد
    }
    super.dispose();
  }

  void _emitIfValid() {
    void emit() {
      final parsed = parseDateField(ctrl.text);
      widget.onChanged(parsed);
    }

    // onChanged والد setState می‌زند — خارج از build همگام، داخل build میکروتسک
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.transientCallbacks) {
      emit();
    } else {
      scheduleMicrotask(emit);
    }
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
        hintText: '۱۴۰۵۰۹۰۴',
        helperText: '۸ رقم یا از تقویم',
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_month),
          tooltip: 'تقویم شمسی',
          onPressed: _pick,
        ),
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹/]'))],
      onChanged: (v) {
        // تعویق میکروتسکی — فرمت/انتشار حین build انجام نمی‌شود
        scheduleMicrotask(() {
          // فرمت هوشمند فقط در حالت تایپ پیوسته ۸ رقمی
          final digits = toEnglishDigits(v).replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.length == 8 && !v.contains('/')) {
            _formatting = true;
            ctrl.text = smartFormatDateInput(v);
            ctrl.selection = TextSelection.fromPosition(
              TextPosition(offset: ctrl.text.length),
            );
            _formatting = false;
          }
          userTyped = true;
          _emitIfValid();
        });
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
