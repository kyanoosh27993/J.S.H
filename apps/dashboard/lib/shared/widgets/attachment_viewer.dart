/// نمایشگر تمام‌صفحه عکس اتچ‌شده — بند ۱۰.۶۳
/// - تصویر با InteractiveViewer (زوم با پینچ و پن با درگ)
/// - سربرگ: نام فایل، یادداشت و تاریخ اتچ
/// - «حذف» با تایید (AttachService.delete)، «چاپ/بازکردن» با نمایشگر سیستم
///   (AttachService.openSystem) و «بستن»
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/attach_service.dart';
import '../../core/utils.dart';

/// سطر اتچ — دقیقاً همان Map برگشتی از AttachService.list
/// کلیدها: id، ticket_id، path، kind، note، created_at
class AttachmentViewerPage extends StatelessWidget {
  final Map<String, Object?> attach;

  /// اگر true برگرداند یعنی عکس حذف شده و caller باید لیست را رفرش کند
  const AttachmentViewerPage({super.key, required this.attach});

  /// باز کردن به‌صورت دیالوگ تمام‌صفحه — خروجی true یعنی حذف شد
  static Future<bool?> open(
      BuildContext context, Map<String, Object?> attach) {
    return showDialog<bool>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (_) => AttachmentViewerPage(attach: attach),
    );
  }

  /// بند ۱۰.۶۳ — ویرایش توضیح عکس اتچ‌شده
  Future<void> _editNote(BuildContext ctx) async {
    final ctrl =
        TextEditingController(text: (attach['note'] ?? '') as String);
    final saved = await showDialog<bool>(
      context: ctx,
      builder: (c2) => AlertDialog(
        title: const Text('ویرایش توضیح عکس'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration:
              const InputDecoration(hintText: 'توضیح این عکس (اختیاری)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c2, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(c2, true),
              child: const Text('ذخیره')),
        ],
      ),
    );
    if (saved != true) return;
    await AttachService.updateNote(attach['id'] as int, ctrl.text.trim());
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx)
          .showSnackBar(const SnackBar(content: Text('توضیح ذخیره شد')));
    }
  }

  Future<void> _delete(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c2) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف عکس'),
          content: const Text('این عکس از سفارش حذف شود؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c2, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(c2, true),
                child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await AttachService.delete((attach['id'] ?? 0) as int);
    if (ctx.mounted) Navigator.pop(ctx, true);
  }

  Future<void> _openSystem(BuildContext ctx) async {
    final mess = ScaffoldMessenger.of(ctx);
    try {
      await AttachService.openSystem((attach['path'] ?? '') as String);
    } catch (e) {
      mess.showSnackBar(SnackBar(
        content: Text('باز کردن با نمایشگر سیستم ممکن نشد: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = (attach['path'] ?? '') as String;
    final note = ((attach['note'] ?? '') as String).trim();
    final createdAt = DateTime.tryParse('${attach['created_at'] ?? ''}');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.basename(path),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              Text(
                [
                  if (createdAt != null) shamsiDateTime(createdAt),
                  if (note.isNotEmpty) 'یادداشت: $note',
                ].join(' — '),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
        body: Center(
          // بند ۱۰.۶۳ — زوم پینچ و جابه‌جایی با درگ
          child: InteractiveViewer(
            maxScale: 8,
            child: Image.file(
              File(path),
              errorBuilder: (_, __, ___) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, size: 56, color: Colors.white38),
                  SizedBox(height: 10),
                  Text('فایل تصویر یافت نشد',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  label: const Text('حذف', style: TextStyle(color: Colors.red)),
                  onPressed: () => _delete(context),
                ),
                // بند ۱۰.۶۳ — اصلاح توضیح عکس اتچ‌شده
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: Colors.amber),
                  label: const Text('ویرایش',
                      style: TextStyle(color: Colors.amber)),
                  onPressed: () => _editNote(context),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('چاپ/بازکردن',
                      style: TextStyle(fontSize: 12.5)),
                  onPressed: () => _openSystem(context),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('بستن'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
