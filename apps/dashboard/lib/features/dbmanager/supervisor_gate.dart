/// دروازه سوپروایزر — قاعده ۹ و ۱۲
library;

import 'package:flutter/material.dart';

import '../../core/services/supervisor_service.dart';
import '../../core/utils.dart';

/// دیالوگ ورود سوپروایزر — نتیجه با true برگردانده می‌شود
Future<bool> showSupervisorGate(BuildContext context, String purpose) async {
  var ok = false;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _GateDialog(purpose: purpose, onOk: () => ok = true),
  );
  return ok;
}

class _GateDialog extends StatefulWidget {
  final String purpose;
  final VoidCallback onOk;
  const _GateDialog({required this.purpose, required this.onOk});

  @override
  State<_GateDialog> createState() => _GateDialogState();
}

class _GateDialogState extends State<_GateDialog> {
  final pwd = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    pwd.dispose();
    super.dispose();
  }

  Future<void> _try() async {
    setState(() {
      busy = true;
      error = '';
    });
    final ok = await SupervisorService.login(pwd.text);
    if (!mounted) return;
    if (ok) {
      widget.onOk();
      Navigator.pop(context);
      return;
    }
    setState(() {
      busy = false;
      if (SupervisorService.isLockedNow) {
        error = '۵ تلاش ناموفق — ورود ۵ دقیقه قفل شد.';
      } else {
        error =
            'رمز نادرست است (تلاش ${toPersianDigits('${SupervisorService.failCount}')} از ۵)';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ورود سوپروایزر'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('این عملیات فقط با اکانت سوپروایزر مجاز است:\n${widget.purpose}',
                style: const TextStyle(fontSize: 12.5, height: 1.7)),
            const SizedBox(height: 10),
            TextField(
              controller: pwd,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'رمز سوپروایزر',
                prefixIcon: Icon(Icons.admin_panel_settings),
              ),
              onSubmitted: (_) => _try(),
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: busy ? null : _try,
          child: Text(busy ? 'بررسی...' : 'ورود'),
        ),
      ],
    );
  }
}
