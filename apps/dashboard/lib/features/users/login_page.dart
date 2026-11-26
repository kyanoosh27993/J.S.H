/// صفحه ورود کاربر — فاز ۲ (بند ۸)
/// ورود اولیه پیش‌فرض admin/admin از قبل در فرم پر است تا کاربر بلافاصله وارد شود؛
/// پس از ورود باید از مدیریت کاربران رمز خود را تغییر دهد.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/services/app_session.dart';
import '../../shared/widgets/app_text.dart';

class LoginPage extends StatefulWidget {
  final AppSession session;
  final VoidCallback onLoggedIn;
  const LoginPage({super.key, required this.session, required this.onLoggedIn});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController userCtrl;
  late final TextEditingController passCtrl;
  bool busy = false;
  String error = '';
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    // بند ۸ — ورود پیش‌فرض admin/admin از قبل در فرم پر است
    userCtrl = TextEditingController(text: 'admin');
    passCtrl = TextEditingController(text: 'admin');
  }

  @override
  void dispose() {
    userCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = '';
    });
    final err = await widget.session.loginWith(userCtrl.text, passCtrl.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        busy = false;
        error = err;
      });
      return;
    }
    widget.onLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.build_circle, size: 54, color: p.primary),
                      const SizedBox(height: 8),
                      AppText(AppInfo.appName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      AppText('ورود به حساب کاربری',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12.5, color: p.outline)),
                      const SizedBox(height: 20),
                      TextField(
                        controller: userCtrl,
                        decoration: const InputDecoration(
                          labelText: 'نام کاربری',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: 'رمز عبور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(obscure
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => obscure = !obscure),
                          ),
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 6),
                      if (error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: AppText(error,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12.5)),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: busy ? null : _login,
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.login),
                          label: const Text('ورود'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Divider(color: p.outline.withValues(alpha: 0.3)),
                      AppText(
                        'ورود پیش‌فرض: admin / admin — پس از ورود، از بخش «کاربران» رمز خود را عوض کنید.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5, color: p.outline, height: 1.7),
                      ),
                      const SizedBox(height: 4),
                      AppText(
                        '${VendorInfo.companyName} — ${VendorInfo.phoneDisplay}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: p.outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
