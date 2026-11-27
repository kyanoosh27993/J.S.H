/// تعطیلات رسمی ایران — قاعده ۳
/// تعطیلات خورشیدی ثابت + تعطیلات قمری متغیر (هر سال توسط صاحب پروژه در map زیر تکمیل می‌شود؛
/// تاریخ قمری هر سال رسمی است و نباید حدس زده شود).
library;

import 'package:shamsi_date/shamsi_date.dart' as j;

/// تعطیلات ثابت خورشیدی — کلید «ماه/روز»
const Map<String, String> kFixedSolarHolidays = {
  '1/1': 'نوروز',
  '1/2': 'عید نوروز',
  '1/3': 'عید نوروز',
  '1/4': 'عید نوروز',
  '1/12': 'روز جمهوری اسلامی',
  '1/13': 'سیزده بدر',
  '3/14': 'رحلت امام خمینی',
  '3/15': 'قیام ۱۵ خرداد',
  '11/22': 'دهه فجر — پیروزی انقلاب اسلامی',
  '12/29': 'روز ملی شدن صنعت نفت',
};

/// تعطیلات قمری/متغیر هر سال — مثال قالب:
/// '1405/9/18': 'اربعین'
/// این map را صاحب پروژه هر سال با تقویم رسمی تکمیل می‌کند؛ مقادیر اینجا خالی است
/// تا هیچ تاریخ ساختگی‌ای در برنامه نمایش داده نشود.
const Map<String, String> kVariableHolidaysByYear = {};

/// نام تعطیلی یا null
String? holidayName(j.Jalali d) {
  final fixed = kFixedSolarHolidays['${d.month}/${d.day}'];
  if (fixed != null) return fixed;
  return kVariableHolidaysByYear['${d.year}/${d.month}/${d.day}'];
}

bool isOfficialHoliday(j.Jalali d) => holidayName(d) != null;

/// جمعه = تعطیل کامل هفتگی؛ پنج‌شنبه = نیم‌تعطیل (رنگ متفاوت)
bool isFriday(j.Jalali d) => d.weekDay == 7;
bool isThursday(j.Jalali d) => d.weekDay == 6;

/// نام روز هفته فارسی
String weekDayName(int weekDay) {
  const names = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه'];
  return names[(weekDay - 1).clamp(0, 6)];
}

String monthName(int month) {
  const names = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];
  return names[(month - 1).clamp(0, 11)];
}
