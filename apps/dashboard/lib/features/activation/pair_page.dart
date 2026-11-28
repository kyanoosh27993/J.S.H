/// دروازه جفت‌سازی اندروید (v0.12.4) — جایگزین فعال‌سازی مستقل
/// ---------------------------------------------------------------------------
/// در هر اجرای برنامه گوشی: اگر جفت نشده → فرم جفت‌سازی؛ اگر جفت شده → تأیید
/// توکن با PC. فقط با PC فعالِ در همان شبکه، برنامه به صفحه ورود می‌رود (بند ۴).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/services/app_session.dart';
import '../../core/services/pair_service.dart';
import '../users/login_page.dart';
import '../shell/shell.dart';

class PairGate extends StatefulWidget {
  final AppSession session;
  final VoidCallback onDone;
  const PairGate({super.key, required this.session, required this.onDone});

  @override
  State<PairGate> createState() => _PairGateState();
}

class _PairGateState extends State<PairGate> {
  PairResult? _last;
  bool _checking = true;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final r = await PairService.verify();
    if (!mounted) return;
    setState(() {
      _last = r;
      _checking = false;
    });
    // v0.12.5 — اگر قبلاً جفت شده، هر ۵ ثانیه خودکار تلاش می‌کنیم تا PC آنلاین
    // شود؛ کاربر دیگر هیچ‌وقت کد جفت‌سازی را دوباره وارد نمی‌کند.
    if (!r.ok && r.error.contains('اتصال به PC برقرار نشد')) {
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 5), () {
        if (mounted) _check();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('در حال اتصال به برنامه ویندوز…'),
            ],
          )),
        ),
      );
    }
    if (_last?.ok != true) {
      return PairForm(
        initialError: _last?.error ?? '',
        onPaired: () {
          widget.onDone();
          setState(() => _checking = true);
          _check();
        },
      );
    }
    // جفت‌سازی سالم → همان دروازه ورود کاربر (بند ۸) → شل
    final s = widget.session;
    if (s.currentUser == null) {
      return LoginPage(session: s, onLoggedIn: widget.onDone);
    }
    return MainShell(session: s, onLogout: widget.onDone);
  }
}

/// فرم جفت‌سازی — آدرس شبکه لوکال PC + کد ۶ رقمی
class PairForm extends StatefulWidget {
  final String initialError;
  final VoidCallback onPaired;
  const PairForm({super.key, required this.initialError, required this.onPaired});

  @override
  State<PairForm> createState() => _PairFormState();
}

class _PairFormState extends State<PairForm> {
  final hostCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError.isEmpty ? null : widget.initialError;
    PairService.host().then((h) {
      if (h != null && mounted) hostCtrl.text = h;
    });
  }

  @override
  void dispose() {
    hostCtrl.dispose();
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await PairService.pair(hostCtrl.text.trim(), codeCtrl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      widget.onPaired();
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.smartphone, size: 44,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text('${AppInfo.appName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('نسخه ${AppInfo.version}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                const Text(
                  'فعال‌سازی این برنامه از طریق کامپیوتر انجام می‌شود:\n'
                  '۱) برنامه ویندوز را باز کنید و در بخش «اتصال موبایل» سرور را روشن کنید.\n'
                  '۲) گوشی را به همان Wi-Fi وصل کنید.\n'
                  '۳) آدرس و کد جفت‌سازی نمایش‌داده‌شده در آن صفحه را اینجا وارد کنید.',
                  style: TextStyle(fontSize: 12.5, height: 1.9),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'آدرس شبکه لوکال کامپیوتر',
                    hintText: 'مثال: 192.168.1.5:3000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'کد جفت‌سازی ۶ رقمی',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text(_busy ? 'در حال اتصال…' : 'اتصال به کامپیوتر'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          // جفت‌ساز قبلی را دور بزن و مستقیم اسکنر را امتحان کن —
                          // اگر PC در شبکه باشد، اسکنر هم اتصال را تأیید می‌کند
                          final r = await PairService.verify();
                          if (r.ok && mounted) {
                            widget.onPaired();
                          } else if (mounted) {
                            setState(() => _error =
                                '${r.error}\nبرای اسکن بارکد/QR اول باید به PC وصل شوید.');
                          }
                        },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('تلاش مجدد اتصال'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
