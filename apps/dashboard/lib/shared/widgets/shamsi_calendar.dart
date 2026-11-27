/// تقویم شمسی کوچک — قاعده ۳
/// انتخاب ساده با کلیک + ورود دستی سال/ماه/روز + سال کبیسه + تعطیلات رسمی رنگی
library;

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart' as j;

import '../../core/utils.dart';
import '../data/holidays.dart';

class ShamsiCalendar extends StatefulWidget {
  final j.Jalali initial;
  final void Function(j.Jalali) onSelected;

  const ShamsiCalendar({
    super.key,
    required this.initial,
    required this.onSelected,
  });

  @override
  State<ShamsiCalendar> createState() => _ShamsiCalendarState();
}

class _ShamsiCalendarState extends State<ShamsiCalendar> {
  late j.Jalali view; // ماه در حال نمایش
  j.Jalali? selected;

  @override
  void initState() {
    super.initState();
    view = widget.initial;
    selected = widget.initial;
  }

  void _go(int deltaMonths) {
    var y = view.year;
    var m = view.month + deltaMonths;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    setState(() {
      view = j.Jalali(y, m, 1);
    });
  }

  void _jumpTo(int year, int month) {
    try {
      setState(() => view = j.Jalali(year, month, 1));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final today = j.Jalali.now();
    final firstWeekDay = j.Jalali(view.year, view.month, 1).weekDay; // 1=شنبه
    final len = j.Jalali(view.year, view.month, 1).monthLength;
    final yearCtrl = TextEditingController(text: '${view.year}');
    final monthCtrl = TextEditingController(text: '${view.month}');

    final cells = <int?>[
      for (var i = 1; i < firstWeekDay; i++) null,
      for (var d = 1; d <= len; d++) d,
    ];

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ناوبری ماه
          // بند ۱۴.۸۶ — فلش‌های RTL: در چیدمان راست‌به‌چپ، دکمه «ماه قبل» باید
          // سمت راست با آیکن chevron_right باشد و «ماه بعد» سمت چپ با chevron_left.
          // Directionality صریح تا در هر زمینه‌ای (دیالوگ، تم، جهت سیستم) چیدمان ثابت بماند.
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'ماه قبل',
                  onPressed: () => _go(-1),
                ),
                Expanded(
                  child: Text(
                    '${monthName(view.month)} ${toPersianDigits('${view.year}')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'ماه بعد',
                  onPressed: () => _go(1),
                ),
              ],
            ),
          ),
          // ورود دستی سال و ماه
          Row(
            children: [
              const SizedBox(width: 8),
              const Text('سال:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              SizedBox(
                width: 62,
                child: TextField(
                  controller: yearCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, counterText: ''),
                  maxLength: 4,
                  onSubmitted: (v) {
                    final y = int.tryParse(toEnglishDigits(v));
                    if (y != null && y >= 1300 && y <= 1500) _jumpTo(y, view.month);
                  },
                ),
              ),
              const SizedBox(width: 10),
              const Text('ماه:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              SizedBox(
                width: 46,
                child: TextField(
                  controller: monthCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, counterText: ''),
                  maxLength: 2,
                  onSubmitted: (v) {
                    final m = int.tryParse(toEnglishDigits(v));
                    if (m != null && m >= 1 && m <= 12) _jumpTo(view.year, m);
                  },
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => widget.onSelected(j.Jalali.now()),
                child: const Text('امروز', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // سرستون روزهای هفته
          Row(
            children: [
              for (var w = 1; w <= 7; w++)
                Expanded(
                  child: Center(
                    child: Text(
                      weekDayName(w).substring(0, w == 1 ? 4 : 2),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: w == 7 ? Colors.red : Colors.blueGrey,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // سلول‌های روزها
          for (var r = 0; r < 6; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _dayCell(cells, r, c, today)),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            'تعطیل رسمی قرمز — پنج‌شنبه کهربایی — جمعه قرمز',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(List<int?> cells, int r, int c, j.Jalali today) {
    final idx = r * 7 + c;
    if (idx >= cells.length || cells[idx] == null) return const SizedBox(height: 34);
    final d = cells[idx]!;
    final date = j.Jalali(view.year, view.month, d);
    final holiday = holidayName(date);
    final friday = isFriday(date);
    final thursday = isThursday(date);
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    final isSelected = selected != null &&
        selected!.year == date.year &&
        selected!.month == date.month &&
        selected!.day == date.day;

    final Color fg = holiday != null || friday
        ? Colors.red.shade700
        : thursday
            ? Colors.deepOrange
            : Colors.black87;

    return InkWell(
      onTap: () {
        setState(() => selected = date);
        widget.onSelected(date);
      },
      child: Container(
        height: 34,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : holiday != null || friday
                  ? Colors.red.shade50
                  : thursday
                      ? Colors.orange.shade50
                      : null,
          border: isToday ? Border.all(color: Colors.blue, width: 1.4) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(toPersianDigits('$d'),
                style: TextStyle(fontSize: 11.5, color: fg, height: 1.0)),
            if (holiday != null)
              Text(holiday,
                  style: TextStyle(fontSize: 6.5, color: Colors.red.shade400, height: 1.0),
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// نمایش پاپ‌آپ تقویم و برگرداندن تاریخ انتخابی (میلیادی)
Future<DateTime?> showShamsiDatePicker(
  BuildContext context, {
  DateTime? initial,
}) async {
  final picked = await showDialog<j.Jalali>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('انتخاب تاریخ شمسی'),
      content: ShamsiCalendar(
        initial: initial != null
            ? j.Jalali.fromDateTime(initial)
            : j.Jalali.now(),
        onSelected: (d) => Navigator.pop(ctx, d),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
      ],
    ),
  );
  return picked?.toDateTime();
}
