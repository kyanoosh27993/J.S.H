/// صفحه پذیرش (F-12-1) — فرم دیجیتال «رسید سپردن» + بیعانه + امضا + PDF + ایمیل + ICS
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signature/signature.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/email_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/reminder_service.dart';
import '../../core/utils.dart';

class IntakePage extends StatefulWidget {
  const IntakePage({super.key});

  @override
  State<IntakePage> createState() => _IntakePageState();
}

class _IntakePageState extends State<IntakePage> {
  List<Customer> customers = [];
  Customer? selected;
  bool newCustomer = false;

  final cName = TextEditingController();
  final cFather = TextEditingController();
  final cNid = TextEditingController();
  final cPhone = TextEditingController();
  final dModel = TextEditingController();
  final dSerial = TextEditingController();
  final defect = TextEditingController();
  final phoneState = TextEditingController();
  final estimate = TextEditingController();
  final deposit = TextEditingController();
  final dueDateCtrl = TextEditingController();
  String dueTime = '18:00';
  final accessories = <String>{};
  bool terms = false;

  final signatureController =
      SignatureController(penStrokeWidth: 3, penColor: Colors.black);

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    for (final c in [cName, cFather, cNid, cPhone, dModel, dSerial, defect, phoneState, estimate, deposit, dueDateCtrl]) {
      c.dispose();
    }
    signatureController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final l = await CustomerRepo.search('');
    if (mounted) setState(() => customers = l);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => dueDateCtrl.text = shamsiDate(picked));
    }
  }

  Future<void> _submit() async {
    final errors = <String>[];
    if (dModel.text.trim().isEmpty) errors.add('مدل دستگاه');
    if (defect.text.trim().isEmpty) errors.add('عیب دستگاه');
    if (!newCustomer && selected == null) errors.add('انتخاب مشتری');
    if (newCustomer && cName.text.trim().isEmpty) errors.add('نام مشتری');
    final due = parseShamsi(dueDateCtrl.text);
    if (due == null) errors.add('تاریخ تحویل (نمونه: ۱۴۰۵/۰۹/۱۰)');
    final estimateVal = int.tryParse(toEnglishDigits(estimate.text)) ?? 0;
    final depositVal = int.tryParse(toEnglishDigits(deposit.text)) ?? 0;
    if (!terms) errors.add('تایید متن اقرارنامه');

    if (errors.isNotEmpty || due == null) {
      await _alert('موارد ناقص', errors.join('، '));
      return;
    }

    // ۱) مشتری
    var customer = selected;
    if (newCustomer || customer == null) {
      customer = Customer(name: cName.text.trim())
        ..fatherName = cFather.text.trim()
        ..nationalId = cNid.text.trim()
        ..phone = cPhone.text.trim();
      customer.id = await CustomerRepo.insert(customer);
    }

    // ۲) دستگاه
    final device = Device(customerId: customer.id!, model: dModel.text.trim())
      ..serial = dSerial.text.trim();
    device.id = await DeviceRepo.insert(device);

    // ۳) سفارش
    final code = await TicketRepo.nextCode();
    final ticket = Ticket(
      code: code,
      customerId: customer.id!,
      deviceId: device.id!,
      intakeDate: DateTime.now(),
      dueDate: due,
      dueTime: dueTime,
      defect: defect.text.trim(),
      phoneState: phoneState.text.trim(),
      estimateAmount: estimateVal,
      depositAmount: depositVal,
      accessories: accessories.toList(),
      termsAccepted: true,
    );
    ticket.id = await TicketRepo.insert(ticket);

    // ۴) بیعانه
    if (depositVal > 0) {
      await PaymentRepo.insert(Payment(
        ticketId: ticket.id!,
        amount: depositVal,
        kind: 'deposit',
      ));
    }

    // ۵) یادآوری با تنظیمات کاربر (N-01)
    final (lead, hour) = await ReminderService.loadPrefs();
    await ReminderService.ensureForTicket(ticket, lead, hour);

    // ۶) PDF رسید
    Uint8List? sig;
    try {
      sig = await signatureController.toPngBytes();
    } catch (_) {}
    final shop = await SettingsRepo.all();
    final pdfPath = await PdfService.buildIntakeReceipt(
      shop: shop,
      ticket: ticket,
      customer: customer,
      device: device,
      signatureBytes: sig ?? Uint8List(0),
    );

    // ۷) ایمیل رسید + رویداد تقویمی (F-06)
    final shopEmail = shop['email'] ?? '';
    if (shopEmail.isNotEmpty && isValidEmail(shopEmail)) {
      final remindAt = due.subtract(Duration(days: lead));
      final ics = EmailService.buildIcs(
        uid: 'ticket-${ticket.id}',
        start: DateTime(remindAt.year, remindAt.month, remindAt.day, hour, 0),
        durationMinutes: 30,
        summary: 'یادآوری تحویل ${ticket.code} — ${device.model}',
        description:
            'یادآوری سفارش ${ticket.code}\nموعد تحویل: ${shamsiDate(due)} $dueTime\n'
            'بیعانه: $depositVal تومان',
        reminderMinutesBefore: 0,
      );
      await EmailQueueRepo.enqueue(
        to: shopEmail,
        subject: 'رسید سفارش ${ticket.code} — ${customer.name}',
        body: 'سفارش جدید ثبت شد.\n'
            'شماره رسید: ${ticket.code}\n'
            'مشتری: ${customer.name} — تلفن: ${customer.phone}\n'
            'دستگاه: ${device.model} — سریال: ${device.serial}\n'
            'موعد تحویل: ${shamsiDate(due)} ساعت $dueTime\n'
            'بیعانه: $depositVal تومان\n'
            'PDF رسید پیوست است و رویداد تقویم یادآوری نیز ضمیمه شده است.',
        attachmentPath: pdfPath,
        icsContent: ics,
      );
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('پذیرش ثبت شد'),
        content: Text(
            'شماره رسید: ${toPersianDigits(code)}\n'
            'یادآوری: ${toPersianDigits('$lead')} روز قبل از موعد، ساعت ${toPersianDigits('$hour:00')}\n'
            'PDF: ${p.basename(pdfPath)}\n'
            'ایمیل رسید در صف ارسال قرار گرفت.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تایید'),
          ),
        ],
      ),
    );
    _reset();
  }

  void _reset() {
    setState(() {
      selected = null;
      newCustomer = false;
      for (final c in [cName, cFather, cNid, cPhone, dModel, dSerial, defect, phoneState, estimate, deposit, dueDateCtrl]) {
        c.clear();
      }
      accessories.clear();
      terms = false;
      dueTime = '18:00';
    });
  }

  Future<void> _alert(String title, String msg) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('خب'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('پذیرش دستگاه — رسید سپردن دیجیتال',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            // مشتری
            Row(
              children: [
                Switch(
                  value: newCustomer,
                  onChanged: (v) => setState(() => newCustomer = v),
                ),
                const Text('مشتری جدید'),
                const SizedBox(width: 14),
                Expanded(
                  child: newCustomer
                      ? const SizedBox.shrink()
                      : DropdownButtonFormField<Customer>(
                          initialValue: selected,
                          items: customers
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text('${c.name} — ${toPersianDigits(c.phone)}'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => selected = v),
                          decoration: const InputDecoration(labelText: 'انتخاب مشتری از CRM'),
                        ),
                ),
              ],
            ),
            if (newCustomer)
              Column(children: [
                _two(cName, 'نام و نام خانوادگی *', cFather, 'نام پدر'),
                _two(cNid, 'شماره ملی', cPhone, 'تلفن همراه'),
              ]),
            const Divider(height: 24),
            // دستگاه
            _two(dModel, 'مدل دستگاه *', dSerial, 'شماره سریال / IMEI'),
            _two(estimate, 'قیمت احتمالی (تومان)', deposit, 'بیعانه دریافتی (تومان)'),
            _two(defect, 'عیب دستگاه اعلامی *', phoneState, 'وضعیت تلفنی دستگاه'),
            // موعد
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: dueDateCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'تاریخ تحویل (شمسی) *',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: _pickDueDate,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: dueTime,
                    items: [
                      for (var h = 8; h <= 21; h++)
                        DropdownMenuItem(
                          value: '${h.toString().padLeft(2, '0')}:00',
                          child: Text('ساعت ${toPersianDigits('${h.toString().padLeft(2, '0')}:00')}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => dueTime = v ?? '18:00'),
                    decoration: const InputDecoration(labelText: 'ساعت تحویل'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // چک‌لیست لوازم
            const Text('لوازم همراه دستگاه:', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 8,
              children: [
                for (final a in Accessory.all)
                  FilterChip(
                    label: Text(a),
                    selected: accessories.contains(a),
                    onSelected: (v) => setState(() {
                      v ? accessories.add(a) : accessories.remove(a);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: terms,
              onChanged: (v) => setState(() => terms = v ?? false),
              title: const Text(
                'متن اقرارنامه فرم سپردن را تایید می‌کنم: «آورنده قبض صحت گوشی شناخته می‌شود؛ در صورت بروز هرگونه مشکل و خاموش شدن گوشی، هیچ‌گونه ادعایی نسبت به این فروشگاه ندارم.»',
                style: TextStyle(fontSize: 12.5, height: 1.8),
              ),
            ),
            const SizedBox(height: 8),
            const Text('امضای مشتری:', style: TextStyle(fontWeight: FontWeight.w600)),
            Container(
              height: 130,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Signature(controller: signatureController),
            ),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('ثبت پذیرش و صدور رسید'),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => signatureController.clear(),
                  child: const Text('پاک کردن امضا'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _two(TextEditingController a, String la, TextEditingController b, String lb) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: TextField(controller: a, decoration: InputDecoration(labelText: la))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: b, decoration: InputDecoration(labelText: lb))),
        ],
      ),
    );
  }
}
