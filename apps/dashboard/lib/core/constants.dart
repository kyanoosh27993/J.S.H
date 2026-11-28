/// ثابت‌های برنامه و اطلاعات شرکت سازنده (نیازمندی N-02)
library;

class VendorInfo {
  static const String companyName = 'آورین سگال بی همتا';
  static const String supportPhone = '09130356250';
  static const String address = 'کرمان، رفسنجان، بلوار طالقانی، نبش کوچه ۵۶ و ۵۸';
  static const String email = 'avrinsegal@gmail.com';
  static const String phoneDisplay = 'تلفن پشتیبانی: ۰۹۱۳۰۳۵۶۲۵۰';
}

class AppInfo {
  static const String appName = 'داشبورد تعمیرات و خدمات';
  static const String projectId = 'J.S.H';
  static const String version = '0.12.7';
  static const String dbFileName = 'jsh_dashboard.db';
  static const int maxInstalls = 3; // نیازمندی F-09
  static const int reportDeadlineDays = 30; // نیازمندی N-03
  static const String logoAsset = 'assets/images/logo.png';
}

/// وضعیت‌های سفارش تعمیر — کلید لاتین برای منطق، برچسب فارسی برای نمایش
class TicketStatus {
  static const String intake = 'intake';
  static const String diagnosis = 'diagnosis';
  static const String waitingPart = 'waiting_part';
  static const String repairing = 'repairing';
  static const String testing = 'testing';
  static const String ready = 'ready';
  static const String delivered = 'delivered';

  static const Map<String, String> labels = {
    intake: 'پذیرش',
    diagnosis: 'تشخیص',
    waitingPart: 'انتظار قطعه',
    repairing: 'تعمیر',
    testing: 'تست',
    ready: 'آماده تحویل',
    delivered: 'تحویل شده',
  };

  /// ترتیب مراحل کارتابل کانبان (S-01)
  static const List<String> order = [
    intake, diagnosis, waitingPart, repairing, testing, ready, delivered,
  ];
}

/// گزینه‌های چک‌لیست لوازم همراه — پیش‌فرض؛ لیست واقعی از تنظیمات خوانده می‌شود (بند ۱۰)
class Accessory {
  static const List<String> all = ['درب پشت', 'باتری', 'مموری', 'سیم کارت'];
}

class ReminderPrefs {
  /// بند ۱ — عدد روز یادآوری دلخواه کاربر (۱ تا ۳۰) — نه فقط ۲/۳/۷
  static const int defaultLeadDays = 3;
  static const int defaultHour = 9;
  static const int minLeadDays = 1;
  static const int maxLeadDays = 30;

  static int clampLeadDays(int d) =>
      d < minLeadDays ? minLeadDays : (d > maxLeadDays ? maxLeadDays : d);
}
