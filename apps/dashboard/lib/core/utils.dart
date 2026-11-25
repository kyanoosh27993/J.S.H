/// ابزارهای مشترک: اعداد فارسی، پول، تاریخ شمسی، اعتبارسنجی
library;

import 'package:shamsi_date/shamsi_date.dart' as j;

String toPersianDigits(String s) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(en[i], fa[i]);
  }
  return s;
}

String toEnglishDigits(String s) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(fa[i], en[i]);
  }
  return s;
}

/// مبلغ به تومان با جداکننده هزارگان و رقم فارسی
String money(num v) {
  final s = v.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return toPersianDigits(s);
}

String moneyToman(num v) => '${money(v)} تومان';

/// تاریخ شمسی از DateTime
String shamsiDate(DateTime dt) {
  final d = j.Jalali.fromDateTime(dt);
  return toPersianDigits('${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}');
}

/// تاریخ + ساعت شمسی
String shamsiDateTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${shamsiDate(dt)} — ${toPersianDigits('$hh:$mm')}';
}

/// پارس «۱۴۰۵/۰۹/۰۴» یا «1405/9/4» به DateTime میلادی (ساعت ۱۲ ظهر برای پایداری)
DateTime? parseShamsi(String input) {
  final s = toEnglishDigits(input.trim()).replaceAll(RegExp(r'[-٫]'), '/');
  final parts = s.split('/');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  final d = int.tryParse(parts[2].trim());
  if (y == null || m == null || d == null) return null;
  try {
    final jDate = j.Jalali(y, m, d);
    return jDate.toDateTime();
  } catch (_) {
    return null;
  }
}

bool isValidEmail(String email) {
  final re = RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
  return re.hasMatch(email.trim());
}

bool isValidIranianMobile(String phone) {
  final s = toEnglishDigits(phone.trim()).replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^09\d{9}$').hasMatch(s) ||
      RegExp(r'^\+989\d{9}$').hasMatch(s);
}

/// انتخاب پیش‌فرض: برچسب وضعیت
String statusLabel(String key) {
  const map = {
    'intake': 'پذیرش',
    'diagnosis': 'تشخیص',
    'waiting_part': 'انتظار قطعه',
    'repairing': 'تعمیر',
    'testing': 'تست',
    'ready': 'آماده تحویل',
    'delivered': 'تحویل شده',
  };
  return map[key] ?? key;
}
