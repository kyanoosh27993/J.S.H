import 'package:flutter_test/flutter_test.dart';

import 'package:jsh_service_dashboard/core/constants.dart';

void main() {
  test('اطلاعات شرکت سازنده ثبت شده است', () {
    expect(VendorInfo.companyName, isNotEmpty);
    expect(VendorInfo.email, contains('@'));
    expect(VendorInfo.supportPhone, isNotEmpty);
  });

  test('سهمیه نصب مجاز ۳ بار است', () {
    expect(AppInfo.maxInstalls, 3);
  });

  test('مراحل کارتابل کامل است', () {
    expect(TicketStatus.order.length, 7);
    expect(TicketStatus.labels[TicketStatus.delivered], 'تحویل شده');
  });
}
