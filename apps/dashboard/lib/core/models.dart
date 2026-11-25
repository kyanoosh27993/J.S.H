/// مدل‌های داده برنامه — نگاشت مستقیم به جداول SQLite
library;

class Customer {
  int? id;
  String name;
  String fatherName;
  String nationalId;
  String phone;
  String address;
  String tag;
  String note;
  String createdAt;

  Customer({
    this.id,
    required this.name,
    this.fatherName = '',
    this.nationalId = '',
    this.phone = '',
    this.address = '',
    this.tag = '',
    this.note = '',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        fatherName: (m['father_name'] ?? '') as String,
        nationalId: (m['national_id'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        tag: (m['tag'] ?? '') as String,
        note: (m['note'] ?? '') as String,
        createdAt: (m['created_at'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'father_name': fatherName,
        'national_id': nationalId,
        'phone': phone,
        'address': address,
        'tag': tag,
        'note': note,
        'created_at': createdAt,
      };
}

class Device {
  int? id;
  int customerId;
  String model;
  String category;
  String serial;
  String note;

  Device({
    this.id,
    required this.customerId,
    required this.model,
    this.category = 'موبایل',
    this.serial = '',
    this.note = '',
  });

  factory Device.fromMap(Map<String, Object?> m) => Device(
        id: m['id'] as int?,
        customerId: m['customer_id'] as int,
        model: (m['model'] ?? '') as String,
        category: (m['category'] ?? 'موبایل') as String,
        serial: (m['serial'] ?? '') as String,
        note: (m['note'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'model': model,
        'category': category,
        'serial': serial,
        'note': note,
      };
}

class Ticket {
  int? id;
  String code;
  int customerId;
  int deviceId;
  DateTime intakeDate;
  DateTime dueDate;
  String dueTime;
  String defect;
  String diagnosis;
  String phoneState;
  int estimateAmount;
  int depositAmount;
  String status;
  List<String> accessories;
  bool termsAccepted;
  String signaturePath;
  String createdAt;
  String updatedAt;

  Ticket({
    this.id,
    this.code = '',
    required this.customerId,
    required this.deviceId,
    required this.intakeDate,
    required this.dueDate,
    this.dueTime = '18:00',
    this.defect = '',
    this.diagnosis = '',
    this.phoneState = '',
    this.estimateAmount = 0,
    this.depositAmount = 0,
    this.status = 'intake',
    List<String>? accessories,
    this.termsAccepted = false,
    this.signaturePath = '',
    String? createdAt,
  })  : accessories = accessories ?? [],
        createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = DateTime.now().toIso8601String();

  factory Ticket.fromMap(Map<String, Object?> m) => Ticket(
        id: m['id'] as int?,
        code: (m['code'] ?? '') as String,
        customerId: m['customer_id'] as int,
        deviceId: m['device_id'] as int,
        intakeDate: DateTime.parse((m['intake_date'] ?? '') as String),
        dueDate: DateTime.parse((m['due_date'] ?? '') as String),
        dueTime: (m['due_time'] ?? '18:00') as String,
        defect: (m['defect'] ?? '') as String,
        diagnosis: (m['diagnosis'] ?? '') as String,
        phoneState: (m['phone_state'] ?? '') as String,
        estimateAmount: (m['estimate_amount'] ?? 0) as int,
        depositAmount: (m['deposit_amount'] ?? 0) as int,
        status: (m['status'] ?? 'intake') as String,
        accessories: _parseAccessories((m['accessories'] ?? '[]') as String),
        termsAccepted: ((m['terms_accepted'] ?? 0) as int) == 1,
        signaturePath: (m['signature_path'] ?? '') as String,
        createdAt: (m['created_at'] ?? '') as String,
      );

  static List<String> _parseAccessories(String s) {
    try {
      final cleaned = s
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .replaceAll('"', '');
      if (cleaned.trim().isEmpty) return [];
      return cleaned.split(',').where((e) => e.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  String get accessoriesJson =>
      '[${accessories.map((a) => '"$a"').join(',')}]';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'code': code,
        'customer_id': customerId,
        'device_id': deviceId,
        'intake_date': intakeDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'due_time': dueTime,
        'defect': defect,
        'diagnosis': diagnosis,
        'phone_state': phoneState,
        'estimate_amount': estimateAmount,
        'deposit_amount': depositAmount,
        'status': status,
        'accessories': accessoriesJson,
        'terms_accepted': termsAccepted ? 1 : 0,
        'signature_path': signaturePath,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

class TicketItem {
  int? id;
  int ticketId;
  String kind; // 'part' | 'service'
  String description;
  int qty;
  int price;
  int? partId;
  int warrantyMonths;
  String createdAt;

  TicketItem({
    this.id,
    required this.ticketId,
    this.kind = 'service',
    required this.description,
    this.qty = 1,
    this.price = 0,
    this.partId,
    this.warrantyMonths = 0,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory TicketItem.fromMap(Map<String, Object?> m) => TicketItem(
        id: m['id'] as int?,
        ticketId: m['ticket_id'] as int,
        kind: (m['kind'] ?? 'service') as String,
        description: (m['description'] ?? '') as String,
        qty: (m['qty'] ?? 1) as int,
        price: (m['price'] ?? 0) as int,
        partId: m['part_id'] as int?,
        warrantyMonths: (m['warranty_months'] ?? 0) as int,
        createdAt: (m['created_at'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ticket_id': ticketId,
        'kind': kind,
        'description': description,
        'qty': qty,
        'price': price,
        'part_id': partId,
        'warranty_months': warrantyMonths,
        'created_at': createdAt,
      };
}

class Payment {
  int? id;
  int ticketId;
  int amount;
  String method; // cash | card | transfer
  String kind; // deposit | final
  String createdAt;

  Payment({
    this.id,
    required this.ticketId,
    required this.amount,
    this.method = 'cash',
    this.kind = 'deposit',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int?,
        ticketId: m['ticket_id'] as int,
        amount: m['amount'] as int,
        method: (m['method'] ?? 'cash') as String,
        kind: (m['kind'] ?? 'deposit') as String,
        createdAt: (m['created_at'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ticket_id': ticketId,
        'amount': amount,
        'method': method,
        'kind': kind,
        'created_at': createdAt,
      };
}

class Reminder {
  int? id;
  int? ticketId;
  String type;
  DateTime remindAt;
  String message;
  String status; // pending | shown | cancelled
  String createdAt;

  Reminder({
    this.id,
    this.ticketId,
    this.type = 'delivery',
    required this.remindAt,
    this.message = '',
    this.status = 'pending',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory Reminder.fromMap(Map<String, Object?> m) => Reminder(
        id: m['id'] as int?,
        ticketId: m['ticket_id'] as int?,
        type: (m['type'] ?? 'delivery') as String,
        remindAt: DateTime.parse((m['remind_at'] ?? '') as String),
        message: (m['message'] ?? '') as String,
        status: (m['status'] ?? 'pending') as String,
        createdAt: (m['created_at'] ?? '') as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ticket_id': ticketId,
        'type': type,
        'remind_at': remindAt.toIso8601String(),
        'message': message,
        'status': status,
        'created_at': createdAt,
      };
}

/// وضعیت لایسنس و گزارش نصب (F-09 + N-03)
class LicenseState {
  int installCount;
  String fingerprint;
  String firstRunAt;
  String consentedAt;
  String userEmail;
  String buyerName;
  String reportStatus; // pending | sent
  String? reportSentAt;
  String lastReportError;
  String hardwareReport;

  LicenseState({
    this.installCount = 1,
    this.fingerprint = '',
    this.firstRunAt = '',
    this.consentedAt = '',
    this.userEmail = '',
    this.buyerName = '',
    this.reportStatus = 'pending',
    this.reportSentAt,
    this.lastReportError = '',
    this.hardwareReport = '',
  });

  bool get reportSent => reportStatus == 'sent';

  factory LicenseState.fromMap(Map<String, Object?> m) => LicenseState(
        installCount: (m['install_count'] ?? 1) as int,
        fingerprint: (m['fingerprint'] ?? '') as String,
        firstRunAt: (m['first_run_at'] ?? '') as String,
        consentedAt: (m['consented_at'] ?? '') as String,
        userEmail: (m['user_email'] ?? '') as String,
        buyerName: (m['buyer_name'] ?? '') as String,
        reportStatus: (m['report_status'] ?? 'pending') as String,
        reportSentAt: m['report_sent_at'] as String?,
        lastReportError: (m['last_report_error'] ?? '') as String,
        hardwareReport: (m['hardware_report'] ?? '') as String,
      );
}
