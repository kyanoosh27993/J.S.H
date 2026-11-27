/// صفحه پذیرش (F-12-1) — فرم دیجیتال «رسید سپردن» — بازطراحی فاز ۴
/// - انتخاب مشتری با جستجو در همه فیلدها (بند ۱۰)
/// - مشخصات مشتری جدید دقیقاً مطابق صفحه مشتریان: نام، نام پدر، کد ملی
///   (۱۰ رقم / شناسه ملی شرکت ۱۱ رقم)، تلفن، آدرس، برچسب (بند ۱۰)
/// - تاریخ پذیرش قابل تغییر (پیش‌فرض امروز) + تاریخ تحویل اختیاری با شمارش
///   روزهای باقیمانده یا «بعد از بررسی اعلام می‌گردد» (بند ۱۰)
/// - «وضعیت ظاهری کالا» به‌جای وضعیت تلفنی؛ پترن قفل به‌جای امضا (بند ۷)
/// - نمایش مانده پیش‌فاکتور و اعلام احتمال افزایش مبلغ (بند ۱۰)
/// - لوازم همراه از تنظیمات (بند ۱۰)؛ پس از ثبت، فرم سه‌برگی A5 (بند ۱۰+۶)
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/a5_receipt_service.dart';
import '../../core/services/app_session.dart';
import '../../core/services/reminder_service.dart';
import '../../core/services/shop_settings_service.dart';
import '../../core/utils.dart';
import '../../shared/widgets/lock_pattern_field.dart';
import '../../shared/widgets/persian_number_field.dart';
import '../../shared/widgets/shamsi_date_field.dart';

class IntakePage extends StatefulWidget {
  const IntakePage({super.key});

  @override
  State<IntakePage> createState() => _IntakePageState();
}

class _IntakePageState extends State<IntakePage> {
  Customer? selected;
  bool newCustomer = false;
  bool terms = false;

  // مشتری جدید — مطابق صفحه مشتریان (بند ۱۰)
  final cName = TextEditingController();
  final cFather = TextEditingController();
  final cNid = TextEditingController();
  final cPhone = TextEditingController();
  final cAddress = TextEditingController();
  final cTag = TextEditingController();

  final dModel = TextEditingController();
  final dSerial = TextEditingController();
  final defect = TextEditingController();
  final phoneState = TextEditingController(); // وضعیت ظاهری کالا
  final estimate = TextEditingController();
  final deposit = TextEditingController();
  final dueDateCtrl = TextEditingController();
  final intakeDateCtrl = TextEditingController();

  DateTime? pickedDue;
  DateTime? pickedIntake;
  String dueTime = '18:00';
  final Set<String> accessories = {};
  List<String> accessoryOptions = [];
  String lockPattern = '';

  // فاز ۲ — واگذاری سفارش برای تشخیص (بند ۸)
  List<Map<String, Object?>> techUsers = [];
  int? _assignTo;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final users = (await UserRepo.list())
        .where((u) => ((u['is_active'] ?? 1) as int) == 1)
        .toList();
    final acc = await ShopSettingsService.loadAccessories();
    if (!mounted) return;
    setState(() {
      techUsers = users;
      accessoryOptions = acc;
      // پیش‌فرض واگذاری: خود کاربر جاری (بند ۸)
      _assignTo ??= AppSession.I.currentUser?.id;
    });
  }

  @override
  void dispose() {
    for (final c in [
      cName,
      cFather,
      cNid,
      cPhone,
      cAddress,
      cTag,
      dModel,
      dSerial,
      defect,
      phoneState,
      estimate,
      deposit,
      dueDateCtrl,
      intakeDateCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // مبلغ با سه‌رقمی جداکننده نمایش داده می‌شود — کاما قبل از پارس حذف شود (بند ۱۹)
  int get _estimateVal =>
      int.tryParse(toEnglishDigits(estimate.text).replaceAll(',', '')) ?? 0;
  int get _depositVal =>
      int.tryParse(toEnglishDigits(deposit.text).replaceAll(',', '')) ?? 0;
  int get _preInvoiceRemaining =>
      _estimateVal - _depositVal > 0 ? _estimateVal - _depositVal : 0;

  Future<void> _submit() async {
    final errors = <String>[];
    if (dModel.text.trim().isEmpty) errors.add('مدل دستگاه');
    if (defect.text.trim().isEmpty) errors.add('عیب دستگاه');
    if (!newCustomer && selected == null) errors.add('انتخاب مشتری');
    if (newCustomer && cName.text.trim().isEmpty) errors.add('نام مشتری');
    if (newCustomer && !isValidNationalId(cNid.text)) {
      errors.add('کد ملی باید ۱۰ رقم و شناسه ملی شرکت ۱۱ رقم باشد');
    }
    if (!terms) errors.add('تایید متن اقرارنامه');

    if (errors.isNotEmpty) {
      await _alert('موارد ناقص', errors.join('، '));
      return;
    }

    // ۱) مشتری — با همه فیلدهای صفحه مشتریان (بند ۱۰)
    var customer = selected;
    if (newCustomer || customer == null) {
      customer = Customer(name: cName.text.trim())
        ..fatherName = cFather.text.trim()
        ..nationalId = cNid.text.trim()
        ..phone = cPhone.text.trim()
        ..address = cAddress.text.trim()
        ..tag = cTag.text.trim();
      customer.id = await CustomerRepo.insert(customer);
    }

    // ۲) دستگاه
    final device = Device(customerId: customer.id!, model: dModel.text.trim())
      ..serial = dSerial.text.trim();
    device.id = await DeviceRepo.insert(device);

    // ۳) سفارش — تاریخ پذیرش قابل تغییر؛ تحویل اختیاری (بند ۱۰)
    final code = await TicketRepo.nextCode();
    final me = AppSession.I.currentUser;
    final intakeDate = pickedIntake ?? DateTime.now();
    final dueUnknown = pickedDue == null;
    final dueDate = pickedDue ?? intakeDate.add(const Duration(days: 7));
    final ticket = Ticket(
      code: code,
      customerId: customer.id!,
      deviceId: device.id!,
      intakeDate: intakeDate,
      dueDate: dueDate,
      dueTime: dueUnknown ? '--:--' : dueTime,
      defect: defect.text.trim(),
      phoneState: phoneState.text.trim(),
      estimateAmount: _estimateVal,
      depositAmount: _depositVal,
      accessories: accessories.toList(),
      termsAccepted: true,
      createdBy: me?.id,
      assignedTo: _assignTo ?? me?.id,
      assignedBy: me?.id,
      assignedAt: DateTime.now().toIso8601String(),
      lockPattern: lockPattern,
      dueUnknown: dueUnknown,
    );
    ticket.id = await TicketRepo.insert(ticket);

    // ۴) بیعانه — با ثبت کاربر وصول‌کننده (بند ۸)
    if (_depositVal > 0) {
      await PaymentRepo.insert(Payment(
        ticketId: ticket.id!,
        amount: _depositVal,
        kind: 'deposit',
        userId: me?.id,
      ));
    }

    // ۵) یادآوری با تنظیمات کاربر (N-01) — فقط برای تحویل بی‌تاریخ معنا دارد
    final (lead, hour) = await ReminderService.loadPrefs();
    if (!dueUnknown) {
      await ReminderService.ensureForTicket(ticket, lead, hour);
    }

    if (!mounted) return;
    // ۶) گفت‌وگوی موفقیت + فرم چاپ سه‌برگی A5 (بند ۱۰ + بند ۶)
    await _successAndPrintDialog(
      ticket: ticket,
      customer: customer,
      device: device,
      code: code,
      lead: lead,
      hour: hour,
      dueUnknown: dueUnknown,
    );
    _reset();
  }

  Future<void> _successAndPrintDialog({
    required Ticket ticket,
    required Customer customer,
    required Device device,
    required String code,
    required int lead,
    required int hour,
    required bool dueUnknown,
  }) async {
    var sheet1 = true; // برگ مشتری
    var sheet2 = true; // برگ فروشگاه
    var sheet3 = false; // برگ بایگانی
    var withLogo = true;
    var withStamp = true;
    var withSignature = true;
    final shop = await SettingsRepo.all();
    final items = await TicketItemRepo.byTicket(ticket.id!);
    if (!mounted) return;
    String? savedPath;
    bool generating = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDState) => AlertDialog(
            title: Text('پذیرش ثبت شد — ${toPersianDigits(code)}'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    dueUnknown
                        ? 'تاریخ تحویل بعد از بررسی دستگاه به مشتری اعلام می گردد.\n'
                            'یادآوری برای سفارش بی‌تاریخ ثبت نمی‌شود.'
                        : 'یادآوری: ${toPersianDigits('$lead')} روز قبل از موعد، ساعت ${toPersianDigits('$hour:00')}',
                    style: const TextStyle(fontSize: 12.5, height: 1.7),
                  ),
                  const Divider(height: 18),
                  const Text('چاپ فرم سه‌برگی A5 — برگه‌های مورد نظر:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: sheet1,
                    onChanged: (v) => setDState(() => sheet1 = v ?? true),
                    title: const Text('برگ مشتری', style: TextStyle(fontSize: 12.5)),
                  ),
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: sheet2,
                    onChanged: (v) => setDState(() => sheet2 = v ?? true),
                    title: const Text('برگ فروشگاه (با جدول اقلام)', style: TextStyle(fontSize: 12.5)),
                  ),
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: sheet3,
                    onChanged: (v) => setDState(() => sheet3 = v ?? false),
                    title: const Text('برگ بایگانی', style: TextStyle(fontSize: 12.5)),
                  ),
                  const Divider(height: 12),
                  const Text('تصاویر فروشگاه در سربرگ (بند ۶):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: withLogo,
                    onChanged: (v) => setDState(() => withLogo = v ?? true),
                    title: const Text('لوگو', style: TextStyle(fontSize: 12.5)),
                  ),
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: withStamp,
                    onChanged: (v) => setDState(() => withStamp = v ?? true),
                    title: const Text('مهر', style: TextStyle(fontSize: 12.5)),
                  ),
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: withSignature,
                    onChanged: (v) => setDState(() => withSignature = v ?? true),
                    title: const Text('امضا', style: TextStyle(fontSize: 12.5)),
                  ),
                  if (generating)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (savedPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('PDF ذخیره شد: $savedPath',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.green, height: 1.6)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تایید'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('ذخیره PDF فرم چاپ'),
                onPressed: generating
                    ? null
                    : () async {
                        setDState(() => generating = true);
                        try {
                          // بند ۱.۱۴ — ساخت بایت‌ها و پرسیدن محل ذخیره از کاربر
                          final bytes = await A5ReceiptService.buildBytes(
                            shop: shop,
                            ticket: ticket,
                            customer: customer,
                            device: device,
                            items: items,
                            sheets: (sheet1, sheet2, sheet3),
                            withLogo: withLogo,
                            withStamp: withStamp,
                            withSignature: withSignature,
                            // فقط متعلقات تیک‌خورده روی فرم علامت می‌خورند (بند ۱.۱۸)
                            selectedAccessories: accessories.toList(),
                          );
                          final path = await A5ReceiptService.saveToUserPath(
                              bytes, '${ticket.code}-A5.pdf');
                          if (path == null) {
                            // کاربر انصراف داد — فایل نوشته نمی‌شود
                            setDState(() => generating = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                content:
                                    Text('ذخیره PDF لغو شد — فایلی ذخیره نشد.'),
                              ));
                            }
                            return;
                          }
                          setDState(() {
                            savedPath = path;
                            generating = false;
                          });
                        } catch (e) {
                          setDState(() => generating = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('خطا در ساخت PDF: $e'),
                              backgroundColor: Colors.red,
                            ));
                          }
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      selected = null;
      newCustomer = false;
      for (final c in [
        cName,
        cFather,
        cNid,
        cPhone,
        cAddress,
        cTag,
        dModel,
        dSerial,
        defect,
        phoneState,
        estimate,
        deposit,
        dueDateCtrl,
        intakeDateCtrl,
      ]) {
        c.clear();
      }
      accessories.clear();
      terms = false;
      pickedDue = null;
      pickedIntake = null;
      dueTime = '18:00';
      lockPattern = '';
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
            // مشتری — سوئیچ + انتخاب با جستجو (بند ۱۰)
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
                      : InkWell(
                          onTap: () async {
                            final c = await _pickCustomerWithResult();
                            if (c != null && mounted) {
                              setState(() => selected = c);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: selected == null
                                  ? 'انتخاب مشتری از CRM (جستجو: نام، تلفن، برچسب...)'
                                  : 'مشتری انتخاب‌شده — برای تغییر کلیک کنید',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                            ),
                            child: Text(
                              selected == null
                                  ? 'کلیک کنید و جستجو کنید'
                                  : '${selected!.name} — ${toPersianDigits(selected!.phone)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: selected == null
                                      ? Theme.of(context).colorScheme.outline
                                      : null),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            if (newCustomer)
              Column(children: [
                _two(cName, 'نام و نام خانوادگی *', cFather, 'نام پدر'),
                _two(cNid, 'کد ملی (۱۰ رقم) / شناسه ملی شرکت (۱۱ رقم)',
                    cPhone, 'تلفن همراه'),
                _two(cAddress, 'آدرس', cTag, 'برچسب'),
              ]),
            const Divider(height: 24),
            // تاریخ پذیرش — بند ۱۰: پیش‌فرض امروز، قابل تغییر
            SizedBox(
              width: 240,
              child: ShamsiDateField(
                label: 'تاریخ پذیرش (شمسی) — پیش‌فرض امروز',
                controller: intakeDateCtrl,
                initial: DateTime.now(),
                onChanged: (dt) => setState(() => pickedIntake = dt),
              ),
            ),
            const SizedBox(height: 4),
            // دستگاه
            _two(dModel, 'مدل دستگاه *', dSerial, 'شماره سریال / IMEI'),
            Row(
              children: [
                Expanded(
                  child: PersianNumberField(
                    label: 'قیمت احتمالی (تومان)',
                    controller: estimate,
                    hint: '0',
                    groupThousands: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PersianNumberField(
                    label: 'بیعانه دریافتی (تومان)',
                    controller: deposit,
                    hint: '0',
                    groupThousands: true,
                  ),
                ),
              ],
            ),
            // بند ۱۰ — مانده پیش‌فاکتور زنده + اعلام احتمال افزایش
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'مانده پیش‌فاکتور: ${moneyToman(_preInvoiceRemaining)} — '
                'این مبلغ ممکن است بعد از بررسی دستگاه اضافه شود.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline, height: 1.6),
              ),
            ),
            // فاز ۲ — واگذاری سفارش به کاربر خاص برای تشخیص (بند ۸)
            Row(
              children: [
                const SizedBox(width: 4),
                const Icon(Icons.handyman, size: 16, color: Colors.deepOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _assignTo,
                    items: [
                      for (final u in techUsers)
                        DropdownMenuItem(
                          value: u['id'] as int,
                          child: Text(
                              'واگذاری برای تشخیص: ${((u['display_name'] ?? '') as String).isEmpty ? u['username'] : u['display_name']}',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _assignTo = v),
                    decoration: const InputDecoration(
                        labelText: 'واگذاری سفارش به کاربر (مسئول تشخیص)'),
                  ),
                ),
              ],
            ),
            _two(defect, 'عیب دستگاه اعلامی *', phoneState, 'وضعیت ظاهری کالا'),
            // موعد تحویل — اختیاری (بند ۱۰) + شمارش روز باقیمانده
            (() {
              final narrow = MediaQuery.of(context).size.width < 480;
              final dateField = ShamsiDateField(
                label: 'تاریخ تحویل (شمسی) — خالی = بعد از بررسی اعلام می‌گردد',
                controller: dueDateCtrl,
                onChanged: (dt) => setState(() => pickedDue = dt),
              );
              final timeField = DropdownButtonFormField<String>(
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
              );
              return Column(children: [
                narrow
                    ? Column(children: [
                        dateField,
                        const SizedBox(height: 8),
                        timeField,
                      ])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: dateField),
                          const SizedBox(width: 10),
                          Expanded(child: timeField),
                        ],
                      ),
                // بند ۱۰ — شمارش روزهای باقیمانده یا اعلام بی‌تاریخی
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    pickedDue == null
                        ? 'تاریخ تحویل بعد از بررسی دستگاه به مشتری اعلام می گردد'
                        : 'روزهای باقیمانده تا تحویل: ${toPersianDigits('${_daysLeft()}')} روز',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: pickedDue == null
                            ? Colors.orange.shade800
                            : Colors.green.shade700),
                  ),
                ),
              ]);
            })(),
            const SizedBox(height: 12),
            // چک‌لیست لوازم — از تنظیمات (بند ۱۰)
            const Text('لوازم همراه دستگاه:', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 8,
              children: [
                for (final a in accessoryOptions)
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
            // بند ۷ — پترن قفل به‌جای محل امضا
            LockPatternField(
              label: 'شکل قفل پترن دستگاه (اگر دارد — بند ۷)',
              initial: lockPattern,
              onChanged: (v) => setState(() => lockPattern = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('ثبت پذیرش و صدور رسید'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _daysLeft() {
    final d = pickedDue;
    if (d == null) return 0;
    final today = DateTime.now();
    return DateTime(d.year, d.month, d.day)
            .difference(DateTime(today.year, today.month, today.day))
            .inDays +
        (pickedIntake != null &&
                DateTime(d.year, d.month, d.day)
                        .difference(DateTime(today.year, today.month, today.day))
                        .inDays <
                    0
            ? 0
            : 0);
  }

  Future<Customer?> _pickCustomerWithResult() async {
    Customer? result;
    final ctrl = TextEditingController();
    List<Customer> results = [];
    result = await showDialog<Customer>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDState) => AlertDialog(
            title: const Text('انتخاب مشتری از CRM'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'هر بخشی از نام / تلفن / کد ملی / برچسب / آدرس',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (q) async {
                      final r = await CustomerRepo.search(q.trim());
                      setDState(() => results = r);
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: results.isEmpty
                        ? const Center(
                            child: Text('چیزی برای نمایش نیست — تایپ کنید',
                                style: TextStyle(fontSize: 12)))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final c = results[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline, size: 18),
                                title: Text(c.name, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  '${toPersianDigits(c.phone)}${c.tag.isEmpty ? '' : ' — ${c.tag}'}'
                                  '${c.address.isEmpty ? '' : ' — ${c.address}'}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onTap: () => Navigator.pop(ctx, c),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف'),
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  Widget _two(TextEditingController a, String la, TextEditingController b, String lb) {
    // فاز ۳ (F-03): روی صفحه باریک گوشی، فیلدهای جفت زیر هم قرار می‌گیرند
    final narrow = MediaQuery.of(context).size.width < 480;
    final fa = TextField(controller: a, decoration: InputDecoration(labelText: la));
    final fb = TextField(controller: b, decoration: InputDecoration(labelText: lb));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: narrow
          ? Column(children: [fa, const SizedBox(height: 8), fb])
          : Row(children: [
              Expanded(child: fa),
              const SizedBox(width: 10),
              Expanded(child: fb),
            ]),
    );
  }
}
