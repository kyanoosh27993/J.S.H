/// تست‌های فاز ۲ — کاربران، دسترسی تفکیکی، اکانت سازنده، واگذاری و قاعده برگشت
/// پوشش بند ۸ (اشکالات) + بند ۲ جدید و قاعده ۱۲ حافظه دائم
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:jsh_service_dashboard/core/db/db.dart';
import 'package:jsh_service_dashboard/core/models.dart';
import 'package:jsh_service_dashboard/core/repos.dart';
import 'package:jsh_service_dashboard/core/services/app_session.dart';
import 'package:jsh_service_dashboard/core/services/auth_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String base;
  _FakePathProvider(this.base);
  @override
  Future<String?> getApplicationSupportPath() async => '$base/support';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$base/docs';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String tempBase;

  setUpAll(() async {
    final t = await Directory.systemTemp.createTemp('jsh_phase2_test');
    tempBase = t.path;
    PathProviderPlatform.instance = _FakePathProvider(tempBase);
  });

  tearDownAll(() async {
    Db.reset();
    try {
      await Directory(tempBase).delete(recursive: true);
    } catch (_) {}
  });

  group('بذر اکانت‌ها', () {
    test('سازنده و مدیر پیش‌فرض پس از باز کردن بانک موجودند', () async {
      final db = await Db.instance();
      final creator = await db.query('users',
          where: 'username = ?', whereArgs: [AuthService.creatorUsername]);
      expect(creator, isNotEmpty);
      expect(creator.first['role'], kRoleCreator);
      // هش ثبت‌شده باید با هش سازنده یکی باشد — رمز خام هرگز در سورس/بانک نیست
      expect(creator.first['password_hash'], AuthService.creatorHash);
      expect((creator.first['password_hash'] as String).length, 64);

      final admin = await db.query('users',
          where: 'username = ?', whereArgs: ['admin']);
      expect(admin, isNotEmpty);
      expect(admin.first['role'], kRoleAdmin);
      // بذر ایده‌مپوتنت — دوباره ensureSeeded، تکراری نمی‌شود
      final countBefore = (await UserRepo.list()).length;
      await AuthService.ensureSeeded();
      expect((await UserRepo.list()).length, countBefore);
    });

    test('اکانت سازنده قابل حذف و ویرایش نیست (قاعده ۱۲)', () async {
      final row = await UserRepo.byUsernameRow(AuthService.creatorUsername);
      final id = row!['id'] as int;
      expect(await UserRepo.delete(id), isNotNull); // پیام خطا، حذف نمی‌شود
      expect(await UserRepo.setPassword(id: id, password: 'x12345'), isNotNull);
      expect(await UserRepo.updateProfile(
          id: id, displayName: 'x', role: kRoleUser, isActive: false, actor: null),
          isNotNull);
      // همچنان موجود است
      expect(await UserRepo.byUsernameRow(AuthService.creatorUsername), isNotNull);
    });
  });

  group('ورود کاربر', () {
    test('admin/admin پیش‌فرض وارد می‌شود', () async {
      final (u, err) = await AuthService.login('admin', 'admin');
      expect(err, isEmpty);
      expect(u, isNotNull);
      expect(u!.isAdmin, isTrue);
    });

    test('رمز اشتباه رد می‌شود و تلاش‌ها شمرده می‌شود', () async {
      final (u, err) = await AuthService.login('admin', 'wrong');
      expect(u, isNull);
      expect(err, isNotEmpty);
      expect(AuthService.failCount, greaterThan(0));
    });

    test('ورود سازنده — رمز فقط از متغیر محیطی (قاعده ۱۲)', () async {
      final pw = Platform.environment['JSH_CREATOR_PW'];
      if (pw == null) {
        // در CI رمز سازنده در دسترس نیست — فقط ساختار هش بررسی می‌شود
        final row = await UserRepo.byUsernameRow(AuthService.creatorUsername);
        expect(row!['password_hash'], AuthService.creatorHash);
        return;
      }
      final (u, err) =
          await AuthService.login(AuthService.creatorUsername, pw);
      expect(err, isEmpty);
      expect(u!.isCreator, isTrue);
      expect(u.can('page.users'), isTrue); // دسترسی کامل
    });
  });

  group('دسترسی تفکیکی (بند ۸)', () {
    late int limitedId;
    test('کاربر محدود با ماتریس دسترسی ساخته می‌شود', () async {
      final (id, err) = await UserRepo.create(
        username: 'tahvil',
        displayName: 'کاربر تحویل',
        role: kRoleUser,
        password: 'pass1234',
      );
      expect(err, isEmpty);
      limitedId = id!;
      // فقط صفحه پذیرش + واگذاری + گذار پذیرش→تشخیص
      await UserRepo.setPerms(limitedId, [
        'page.home',
        'page.intake',
        'action.intake.create',
        'action.delegation.assign',
        'status.intake__diagnosis',
      ]);
      final u = await UserRepo.byId(limitedId);
      expect(u!.isAdmin, isFalse);
      expect(u.can('page.intake'), isTrue);
      expect(u.can('status.intake__diagnosis'), isTrue);
      expect(u.can('page.users'), isFalse); // مدیریت کاربران ممنوع
      expect(u.can('status.diagnosis__waiting_part'), isFalse);
      expect(u.can('action.ticket.settle'), isFalse);
    });
  });

  group('واگذاری، تاریخچه و قاعده برگشت', () {
    late int ticketId;
    late int limitedId;
    late int adminId;

    setUpAll(() async {
      final (_, err) = await UserRepo.create(
        username: 'tech1',
        displayName: 'تکنسین یکم',
        role: kRoleUser,
        password: 'techpass',
      );
      expect(err, isEmpty);
      final limited = await UserRepo.byUsernameRow('tahvil');
      limitedId = limited!['id'] as int;
      final admin = await UserRepo.byUsernameRow('admin');
      adminId = admin!['id'] as int;

      final cId = await CustomerRepo.insert(Customer(name: 'مشتری تست فاز۲'));
      final dId = await DeviceRepo.insert(
          Device(customerId: cId, model: 'iPhone 12'));
      ticketId = await TicketRepo.insert(Ticket(
        customerId: cId,
        deviceId: dId,
        intakeDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 3)),
        createdBy: limitedId,
        assignedTo: adminId,
      ));
    });

    test('تغییر وضعیت کاربر/دلیل/واگذاری را ثبت می‌کند', () async {
      await TicketRepo.changeStatus(
        ticketId,
        'diagnosis',
        userId: limitedId,
        reason: 'دست دادن به تکنسین',
        assignTo: adminId,
      );
      final t = await TicketRepo.byId(ticketId);
      expect(t!.status, 'diagnosis');
      expect(t.assignedTo, adminId);
      expect(t.assignedBy, limitedId);
      expect(t.assignedAt, isNotEmpty);
      final log = await TicketRepo.statusLog(ticketId);
      expect(log.last['from_status'], 'intake');
      expect(log.last['to_status'], 'diagnosis');
      expect(log.last['user_id'], limitedId);
      expect(log.last['reason'], 'دست دادن به تکنسین');
    });

    test('برگشت فقط توسط تغییردهندهٔ آخر — کاربر دیگر ممنوع', () async {
      final tech = await UserRepo.byUsernameRow('tech1');
      final techUser = await UserRepo.byId(tech!['id'] as int);
      // tech1 آخرین تغییر را نداده — برگشت ممنوع
      expect(await TicketRepo.canRevert(ticketId, techUser), isFalse);
      final limited = await UserRepo.byId(limitedId);
      // تغییردهندهٔ آخر همان tahvil است — برگشت مجاز
      expect(await TicketRepo.canRevert(ticketId, limited), isTrue);
      // برگشت واقعی با دلیل الزامی
      await TicketRepo.changeStatus(
        ticketId,
        'intake',
        userId: limitedId,
        reason: 'کار پذیرفته نشد',
      );
      final t = await TicketRepo.byId(ticketId);
      expect(t!.status, 'intake');
      final log = await TicketRepo.statusLog(ticketId);
      expect(log.last['to_status'], 'intake');
      expect(log.last['from_status'], 'diagnosis');
    });

    test('مدیر همیشه حق برگشت دارد', () async {
      await TicketRepo.changeStatus(ticketId, 'diagnosis',
          userId: adminId, reason: 'ارسال برای تشخیص');
      final tech = await UserRepo.byUsernameRow('tech1');
      final techUser = await UserRepo.byId(tech!['id'] as int);
      // آخرین تغییردهنده مدیر است — تکنسین ممنوع، مدیر مجاز
      expect(await TicketRepo.canRevert(ticketId, techUser), isFalse);
      final admin = await UserRepo.byId(adminId);
      expect(await TicketRepo.canRevert(ticketId, admin), isTrue);
    });

    test('واگذاری بدون تغییر وضعیت ثبت می‌شود', () async {
      await TicketRepo.assign(ticketId, limitedId, adminId);
      final t = await TicketRepo.byId(ticketId);
      expect(t!.status, 'diagnosis'); // وضعیت ثابت مانده
      expect(t.assignedTo, limitedId);
      final log = await TicketRepo.statusLog(ticketId);
      expect(log.last['assigned_to'], limitedId);
    });
  });

  group('گزارش عملکرد کاربران (بند ۸)', () {
    test('وصولی و شمارش کارها بر اساس کاربر جمع می‌شود', () async {
      final limited = await UserRepo.byUsernameRow('tahvil');
      final lid = limited!['id'] as int;
      // بازه گزارش — قبل از ثبت سفارش گرفته می‌شود تا شمارش درست باشد
      final fromIso = DateTime.now().toIso8601String();
      // سفارش واقعی برای درستی کلید خارجی پرداخت
      final cId = await CustomerRepo.insert(Customer(name: 'مشتری گزارش'));
      final dId = await DeviceRepo.insert(
          Device(customerId: cId, model: 'Samsung A52'));
      final tid = await TicketRepo.insert(Ticket(
        code: 'T-PERF-1',
        customerId: cId,
        deviceId: dId,
        intakeDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 2)),
        createdBy: lid,
      ));
      await PaymentRepo.insert(Payment(
        ticketId: tid,
        amount: 500000,
        kind: 'final',
        userId: lid,
      ));
      final rows = await TicketRepo.activityReport(
        fromIso,
        DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      );
      final me = rows.firstWhere((r) => (r['id'] as int) == lid);
      expect((me['collected'] ?? 0) as int, 500000);
      // یک پذیرش ثبت‌شده توسط همین کاربر در همین بازه
      expect((me['intakes'] ?? 0) as int, 1);
      final total = rows.fold<int>(0, (s, r) => s + ((r['collected'] ?? 0) as int));
      expect(total, 500000);
      // سهم ۱۰۰٪
      expect(((me['share'] ?? 0.0) as num).toDouble(), closeTo(100, 0.1));
    });
  });

  group('نشست برنامه', () {
    test('loginWith کاربر جاری را ست و logout پاک می‌کند', () async {
      final s = AppSession.I;
      expect(s.currentUser, isNull);
      final err = await s.loginWith('admin', 'admin');
      expect(err, isNull);
      expect(s.currentUser, isNotNull);
      expect(s.can('page.users'), isTrue);
      await s.logout();
      expect(s.currentUser, isNull);
      expect(s.can('page.users'), isFalse);
    });
  });
}
