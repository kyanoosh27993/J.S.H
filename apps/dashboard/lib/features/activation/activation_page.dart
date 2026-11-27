/// صفحه فعال‌سازی — فاز ۱ (بند ۴ درخواست صاحب پروژه)
/// پس از نصب و ورود اطلاعات پایه خریدار، مشخصات سازنده نمایش داده می‌شود،
/// شناسه منحصربه‌فرد دستگاه نشان داده می‌شود و تنها با وارد کردن کد فعال‌سازی،
/// برنامه راه‌اندازی می‌شود — روی ویندوز و اندروید یکسان.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/services/activation_service.dart';
import '../../core/services/app_session.dart';
import '../../core/utils.dart';

class ActivationPage extends StatefulWidget {
  final AppSession session;
  final VoidCallback onActivated;
  const ActivationPage({
    super.key,
    required this.session,
    required this.onActivated,
  });

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final codeCtrl = TextEditingController();
  String deviceId = '';
  String error = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    ActivationService.deviceId().then((v) {
      if (mounted) setState(() => deviceId = v);
    });
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final err = await widget.session.activateWithCode(codeCtrl.text);
      if (err != null) {
        setState(() => error = err);
      } else {
        widget.onActivated();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('فعال‌سازی برنامه — ${AppInfo.appName}'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                // مشخصات سازنده (بند ۴)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.business, size: 20),
                          SizedBox(width: 8),
                          Text(VendorInfo.companyName,
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                            'تلفن پشتیبانی: ${toPersianDigits(VendorInfo.supportPhone)}',
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        const Text(VendorInfo.address,
                            style: TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Text('ایمیل: ${VendorInfo.email}',
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'شماره شناسه دستگاه شما',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'این شماره از مادربورد و پردازنده این دستگاه ساخته می‌شود و منحصربه‌فرد است. '
                  'آن را برای سازنده بفرستید تا کد فعال‌سازی دریافت کنید.',
                  style: TextStyle(fontSize: 12.5, height: 1.8),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        deviceId.isEmpty
                            ? 'در حال خواندن شناسه سخت‌افزار...'
                            : ActivationService.displayDeviceId(deviceId),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: deviceId.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                    ClipboardData(text: deviceId));
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('شناسه دستگاه کپی شد')),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('کپی شناسه دستگاه'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: codeCtrl,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'کد فعال‌سازی',
                    hintText: 'JSH-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(error,
                        style: TextStyle(
                            fontSize: 13, color: cs.onErrorContainer)),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : _submit,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.key_rounded),
                  label: const Text('فعال‌سازی برنامه'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'کد فعال‌سازی فقط برای همین دستگاه معتبر است و مدت اعتبار و سقف نصب آن '
                  'را سازنده تعیین می‌کند. این برنامه بدون کد فعال‌سازی اجرا نمی‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, height: 1.8, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
