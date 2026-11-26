/// سرویس تحویل — فاز ۳ (بند ۱۱)
/// تغییر وضعیت «آماده تحویل» به «تحویل داده شده» فقط با تاییدیه انجام می‌شود؛
/// اگر تسویه نشده باشد، کاربر انتخاب می‌کند: تسویه کامل و تحویل، یا تحویل با
/// بدهی با تایید صریح. پس از تحویل، رکورد فاکتور سفارش در جدول invoices
/// ساخته می‌شود (پیش‌فاکتور → فاکتور) و همه‌چیز با کاربر و تاریخ ثبت می‌شود.
/// شماره‌گذاری استاندارد فاکتور در فاز ۵ جایگزین شماره موقت می‌شود.
library;

import '../models.dart';
import '../repos.dart';
import '../warranty.dart';
import 'app_session.dart';
import 'supervisor_service.dart' show AuditRepo;

enum DeliveryDecision {
  /// تسویه کامل باقیمانده و سپس تحویل
  settleAndDeliver,

  /// تحویل با بدهی — تایید صریح کاربر
  deliverWithDebt,
}

class DeliveryResult {
  final bool ok;
  final String message; // پیام فارسی برای اسنک‌بار
  final int invoiceId;
  const DeliveryResult(this.ok, this.message, {this.invoiceId = 0});
}

class DeliveryService {
  /// جمع فاکتور سفارش: اقلام ثبت‌شده یا برآورد اولیه
  static Future<int> totalOf(Ticket t) async {
    final items = await TicketItemRepo.byTicket(t.id!);
    final sum = items.fold<int>(0, (s, i) => s + i.price * i.qty);
    return sum > 0 ? sum : t.estimateAmount;
  }

  /// باقیمانده تسویه سفارش
  static Future<int> remainingOf(Ticket t) async {
    final paid = await PaymentRepo.paidSum(t.id!);
    return (await totalOf(t)) - paid;
  }

  /// ساخت/به‌روزرسانی رکورد فاکتور سفارش تحویل‌شده — پیش‌فاکتور → فاکتور
  static Future<int> ensureInvoice(Ticket t, int userId) async {
    // فاز ۵ — شماره‌گذاری استاندارد سال+روز+۴رقمی از طریق InvoiceRepo
    return InvoiceRepo.createFromTicket(ticket: t, kind: InvoiceRepo.kindFinal);
  }

  /// انجام تحویل — تصمیم را ثبت‌کننده UI می‌گیرد (دیالوگ تاییدیه)
  /// اگر settleAndDeliver باشد، باقیمانده به‌عنوان پرداخت نهایی با کاربر
  /// وصول‌کننده ثبت و سپس تحویل انجام می‌شود.
  static Future<DeliveryResult> deliver(
    Ticket t, {
    required DeliveryDecision decision,
  }) async {
    final me = AppSession.I.currentUser;
    final userId = me?.id ?? 0;
    final remaining = await remainingOf(t);

    if (remaining > 0 && decision == DeliveryDecision.settleAndDeliver) {
      await PaymentRepo.insert(Payment(
        ticketId: t.id!,
        amount: remaining,
        kind: 'final',
        userId: me?.id,
      ));
      await AuditRepo.log('settle',
          'تسویه کامل سفارش #${t.id} به مبلغ $remaining — کاربر #$userId');
    }

    // تغییر وضعیت با ثبت کاربر و دلیل (بند ۱۱ + بند ۸)
    await TicketRepo.changeStatus(
      t.id!,
      'delivered',
      userId: userId,
      reason: decision == DeliveryDecision.settleAndDeliver
          ? 'تحویل با تاییدیه و تسویه کامل حساب'
          : (remaining > 0
              ? 'تحویل با بدهی $remaining تومان — تایید صریح کاربر'
              : 'تحویل با تاییدیه — حساب تسویه است'),
      note: 'تاییدیه تحویل ثبت شد',
    );

    // گارانتی خودکار هنگام تحویل
    try {
      final months = await WarrantyRepo.defaultMonths();
      await WarrantyRepo.upsertForTicket(t.id!, months);
    } catch (_) {}

    // پیش‌فاکتور → فاکتور
    final invId = await ensureInvoice(t, userId);

    return DeliveryResult(
      true,
      remaining > 0 && decision == DeliveryDecision.settleAndDeliver
          ? 'تسویه کامل و تحویل ثبت شد — فاکتور صادر شد'
          : 'تحویل ثبت شد — فاکتور صادر شد',
      invoiceId: invId,
    );
  }
}
