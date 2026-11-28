/// صفحه سفارشات — فاز ۵ (بند ۱۲)
/// لیست همه سفارشات پذیرش‌شده با کلیه جزئیات؛ صدور پیش‌فاکتور برای سفارشات
/// قبل از تحویل و فاکتور فروش برای تحویل‌شده‌ها؛ جستجو/فیلتر؛ QR سند؛
/// باز کردن سند با تایپ شماره (بند ۶ جدید).
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/services/mobile_link_service.dart';
import '../../core/models.dart';
import '../../core/repos.dart';
import '../../core/services/a5_receipt_service.dart';
import '../../core/services/app_session.dart';
import '../../core/services/auth_service.dart' show kRoleCreator;
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/data_table_pro.dart';
import '../../shared/widgets/persian_number_field.dart';
import '../../shared/widgets/qr_box.dart';
import '../tickets/ticket_detail.dart';
import 'barcode_scanner.dart';

/// نتیجه دیالوگ کادر هزینه/تخفیف/خسارت — بند ۱۲
typedef _Financials = ({
  int cost,
  int discount,
  int damage,
  int? damageUserId,
  String note,
});

/// کادر هزینه/تخفیف/خسارت + انتخاب کاربر خسارت‌زننده (بند ۱۲)
/// فقط هنگام صدور فاکتور قطعی یا «اصلاح مبالغ» نمایش داده می‌شود.
Future<_Financials?> showFinancialsDialog(
  BuildContext context, {
  int cost = 0,
  int discount = 0,
  int damage = 0,
  int? damageUserId,
  String note = '',
}) async {
  final costCtrl = TextEditingController(text: '$cost');
  final discCtrl = TextEditingController(text: '$discount');
  final dmgCtrl = TextEditingController(text: '$damage');
  final noteCtrl = TextEditingController(text: note);
  int? dmgUser = damageUserId;
  final users = (await UserRepo.list())
      .where((u) => ((u['is_active'] ?? 1) as int) == 1 &&
          (u['role'] ?? '') != kRoleCreator)
      .toList();
  return showDialog<_Financials>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, sbSet) => AlertDialog(
          title: const Text('هزینه، تخفیف و خسارت (بند ۱۲)'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PersianNumberField(
                    label: 'هزینه (تومان)', controller: costCtrl, hint: '0'),
                const SizedBox(height: 8),
                PersianNumberField(
                    label: 'تخفیف (تومان)', controller: discCtrl, hint: '0'),
                const SizedBox(height: 8),
                PersianNumberField(
                    label: 'خسارت (تومان)', controller: dmgCtrl, hint: '0'),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  value: dmgUser,
                  decoration: const InputDecoration(
                    labelText: 'کاربر خسارت‌زننده (در صورت وارد کردن خسارت)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('— بدون کاربر —')),
                    for (final u in users)
                      DropdownMenuItem<int?>(
                        value: u['id'] as int?,
                        child: Text(
                            '${(u['display_name'] ?? '') as String} (${u['username']})'),
                      ),
                  ],
                  onChanged: (v) => sbSet(() => dmgUser = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت سود (اختیاری)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                int parse(TextEditingController c) => int.tryParse(
                        toEnglishDigits(c.text).replaceAll(',', '')) ??
                    0;
                Navigator.pop(
                  ctx,
                  (
                    cost: parse(costCtrl),
                    discount: parse(discCtrl),
                    damage: parse(dmgCtrl),
                    damageUserId:
                        parse(dmgCtrl) > 0 ? dmgUser : null,
                    note: noteCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// چاپ/PDF رسید سه‌برگی سفارش — بند ۱۰.۷۱ (بدون دیالوگ؛ برگ مشتری)
Future<void> printTicketReceipt(BuildContext context, Ticket t) async {
  final mess = ScaffoldMessenger.of(context);
  try {
    final shop = await SettingsRepo.all();
    final customer = await CustomerRepo.byId(t.customerId);
    final device = await DeviceRepo.byId(t.deviceId);
    if (customer == null || device == null) {
      throw Exception('مشتری یا دستگاه سفارش یافت نشد');
    }
    final items = await TicketItemRepo.byTicket(t.id!);
    final path = await A5ReceiptService.build(
      shop: shop,
      ticket: t,
      customer: customer,
      device: device,
      items: items,
      sheets: (true, false, false),
    );
    mess.showSnackBar(SnackBar(
        content: Text('PDF رسید ذخیره شد: ${toPersianDigits(path)}')));
  } catch (e) {
    mess.showSnackBar(SnackBar(
      content: Text('خطا در ساخت PDF: $e'),
      backgroundColor: Colors.red,
    ));
  }
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool loading = true;
  List<Ticket> tickets = [];
  Map<int, String> customerNames = {};
  Map<int, Map<String, Object?>> invoicesByTicket = {};

  // بند ۱۰.۶۰ — نتیجه اسکن بارکد برای جستجو (null = بدون فیلتر اسکن)
  String? scanQuery;

  // قابلیت‌های موبایل (اسکنر) فقط روی اندروید
  bool get _isMobile => !kIsWeb && Platform.isAndroid;

  /// بند ۱۰.۶۰ — اسکن بارکد و فیلتر همان جدول (مثل تایپ در کادر جستجو)؛
  /// کادر جستجو داخل DataTablePro است، پس فیلتر از بیرون روی سطرها اعمال می‌شود.
  Future<void> _scanAndFilter() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted) return;
    final c = (code ?? '').trim();
    if (c.isEmpty) return;
    setState(() => scanQuery = c);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('جستجو با بارکد: ${toPersianDigits(c)}'),
    ));
  }

  /// سطرهای نمایان با فیلتر اسکن — شامل تبدیل ارقام فارسی/انگلیسی
  List<Ticket> get _visibleTickets {
    final q = scanQuery?.trim();
    if (q == null || q.isEmpty) return tickets;
    final qEn = toEnglishDigits(q);
    return tickets.where((t) {
      final idx = '${t.code} ${customerNames[t.customerId] ?? ''}';
      return idx.contains(q) || idx.contains(qEn);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // یک ردیف خراب نباید کل صفحه را خالی کند (بند ۲۰ نسخه ۳)
    try {
      await _loadData();
    } catch (e) {
      debugPrint('orders _load error: $e');
    }
  }

  Future<void> _loadData() async {
    final ts = await TicketRepo.all();
    final cNames = await CustomerRepo.nameMap();
    final invoices = await InvoiceRepo.allByTicketMap();
    if (!mounted) return;
    setState(() {
      tickets = ts;
      customerNames = cNames;
      invoicesByTicket = invoices;
      loading = false;
    });
  }

  /// صدور سند — پیش‌فاکتور برای قبل از تحویل، فاکتور فروش برای تحویل‌شده (بند ۱۲)
  Future<void> _issue(Ticket t) async {
    final me = AppSession.I.currentUser;
    if (!me!.can('action.invoice.edit')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی صدور فاکتور برای شما مجاز نیست'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final isDelivered = t.status == TicketStatus.delivered;
    final kind = isDelivered ? InvoiceRepo.kindFinal : InvoiceRepo.kindPre;
    // بند ۱۲ — فاکتور قطعی: کادر هزینه/تخفیف/خسارت + کاربر خسارت‌زننده
    _Financials? fin;
    if (isDelivered) {
      fin = await showFinancialsDialog(context);
      if (fin == null) return; // انصراف از صدور
    }
    final id = await InvoiceRepo.createFromTicket(
      ticket: t,
      kind: kind,
      cost: fin?.cost,
      discount: fin?.discount ?? 0,
      damage: fin?.damage,
      damageUserId: fin?.damageUserId,
      profitNote: fin?.note,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isDelivered
          ? 'فاکتور فروش صادر شد (شناسه ${toPersianDigits('$id')})'
          : 'پیش‌فاکتور صادر شد (شناسه ${toPersianDigits('$id')})'),
    ));
    _load();
  }

  /// باز کردن سند با تایپ شماره — بند ۶ جدید
  Future<void> _lookupByNumber() async {
    final ctrl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('باز کردن سند با شماره'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'شماره فاکتور یا کد سفارش (بند ۶ جدید)',
              hintText: 'مثلاً 14050905-0001 یا RCP-20261126-001',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            // v0.12.5 — اسکن QR فاکتور با دوربین گوشیِ متصل (سرور پورت 3000)
            StreamBuilder<String>(
              stream: MobileLinkService.scanEvents,
              builder: (ctx, snap) {
                final got = snap.data?.trim();
                if (got != null && got.isNotEmpty) {
                  // اسکن رسید → بستن دیالوگ با همان کد
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (ctx.mounted) Navigator.pop(ctx, got);
                  });
                }
                return TextButton.icon(
                  onPressed: null,
                  icon: Icon(
                      got == null || got.isEmpty
                          ? Icons.phonelink_ring
                          : Icons.check_circle,
                      size: 18,
                      color: got == null || got.isEmpty
                          ? null
                          : Colors.green),
                  label: Text(
                      got == null || got.isEmpty
                          ? 'منتظر اسکن QR از دوربین گوشی…'
                          : 'دریافت شد: $got',
                      style: const TextStyle(fontSize: 12)),
                );
              },
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('باز کردن')),
          ],
        ),
      ),
    );
    if (q == null || q.trim().isEmpty) return;
    final invoice = await InvoiceRepo.findByNumberOrCode(q);
    if (!mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('سندی با شماره «${toPersianDigits(q.trim())}» یافت نشد'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final ticketId = invoice['ticket_id'] as int;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketDetailPage(ticketId: ticketId),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppSession.I.currentUser;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('سفارشات پذیرش‌شده',
                  style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('به‌روزرسانی'),
              ),
              OutlinedButton.icon(
                onPressed: _lookupByNumber,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('باز کردن با شماره / QR'),
              ),
              // بند ۱۰.۶۰ — جستجوی بارکدی؛ فقط موبایل
              if (_isMobile)
                OutlinedButton.icon(
                  onPressed: _scanAndFilter,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('اسکن بارکد جستجو'),
                ),
              if (scanQuery != null && scanQuery!.trim().isNotEmpty)
                FilterChip(
                  label: Text(
                      'فیلتر اسکن: ${toPersianDigits(scanQuery!.trim())}',
                      style: const TextStyle(fontSize: 12)),
                  onSelected: null,
                  onDeleted: () => setState(() => scanQuery = null),
                ),
              AppText(
                'کاربر: ${me?.bestName ?? '-'}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : tickets.isEmpty
                    ? const Center(child: Text('سفارشی ثبت نشده است'))
                    : SingleChildScrollView(
                        child: DataTablePro<Ticket>(
                          // بند ۱۰.۶۰ — سطرها با نتیجه اسکن بارکد فیلتر شده‌اند
                          rows: _visibleTickets,
                          tableId: 'orders',
                          searchIndex: (t) =>
                              '${t.code} ${customerNames[t.customerId] ?? ''}',
                          onRowTap: (t) async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TicketDetailPage(ticketId: t.id!),
                              ),
                            );
                            _load();
                          },
                          columns: [
                            ProColumn<Ticket>(
                              label: 'کد سفارش',
                              display: (t) => t.code,
                              width: 150,
                            ),
                            ProColumn<Ticket>(
                              label: 'مشتری',
                              display: (t) =>
                                  customerNames[t.customerId] ?? '-',
                              width: 150,
                              filterable: true,
                            ),
                            ProColumn<Ticket>(
                              label: 'وضعیت',
                              display: (t) => statusLabel(t.status),
                              width: 100,
                              filterable: true,
                            ),
                            ProColumn<Ticket>(
                              label: 'پذیرش',
                              display: (t) => shamsiDate(t.intakeDate),
                              width: 100,
                            ),
                            ProColumn<Ticket>(
                              label: 'موعد',
                              display: (t) => t.dueUnknown
                                  ? 'بعد از بررسی'
                                  : shamsiDate(t.dueDate),
                              width: 100,
                            ),
                            ProColumn<Ticket>(
                              label: 'سند',
                              display: (t) {
                                final inv = invoicesByTicket[t.id];
                                if (inv == null) return '—';
                                return '${(inv['kind'] ?? '') == InvoiceRepo.kindFinal ? 'فاکتور' : 'پیش‌فاکتور'} ${toPersianDigits((inv['number'] ?? '') as String)}';
                              },
                              width: 190,
                            ),
                          ],
                          rowAction: (t) => Wrap(
                            spacing: 6,
                            children: [
                              QrBox(
                                  data:
                                      '${t.code} ${(invoicesByTicket[t.id]?['number'] ?? '')}'),
                              // بند ۱۰.۷۱ — چاپ/PDF رسید از لیست سفارشات
                              IconButton(
                                tooltip: 'چاپ/PDF رسید',
                                icon: const Icon(Icons.picture_as_pdf,
                                    size: 18),
                                onPressed: () => printTicketReceipt(context, t),
                              ),
                              if (me?.can('action.invoice.edit') ?? false)
                                IconButton(
                                  tooltip: t.status == TicketStatus.delivered
                                      ? 'صدور فاکتور فروش'
                                      : 'صدور پیش‌فاکتور',
                                  icon: Icon(
                                    t.status == TicketStatus.delivered
                                        ? Icons.receipt
                                        : Icons.request_quote_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => _issue(t),
                                ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
