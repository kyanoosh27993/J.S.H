/// صفحه «اتصال موبایل» (v0.12.4) — سرور لوکال پورت 3000، آدرس شبکه، کد جفت‌سازی
/// و فهرست گوشی‌های متصل. فقط روی دسکتاپ معنا دارد.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/services/mobile_link_service.dart';

class MobileLinkPage extends StatefulWidget {
  const MobileLinkPage({super.key});

  @override
  State<MobileLinkPage> createState() => _MobileLinkPageState();
}

class _MobileLinkPageState extends State<MobileLinkPage> {
  @override
  void initState() {
    super.initState();
    MobileLinkService.state.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    MobileLinkService.state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final st = MobileLinkService.state.value;
    if (st.running) {
      await MobileLinkService.stop();
    } else {
      await MobileLinkService.start();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final st = MobileLinkService.state.value;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Icon(st.running ? Icons.wifi_tethering : Icons.wifi_off,
                color: st.running ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            Text('اتصال موبایل — ${st.running ? 'فعال' : 'خاموش'}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(st.running ? Icons.stop : Icons.play_arrow),
              label: Text(st.running ? 'توقف سرور' : 'شروع سرور'),
            ),
          ]),
          const SizedBox(height: 12),
          const Text(
            'برنامه ویندوز فعال‌شده، یک شبکه لوکال روی پورت 3000 می‌سازد. '
            'گوشی را به همان Wi-Fi وصل کنید، در برنامه موبایل این آدرس را وارد و '
            'کد جفت‌سازی را بزنید؛ از این پس ورود گوشی فقط با اتصال به این شبکه '
            'انجام می‌شود و دوربین گوشی برای اسکن بارکد/QR، عکس‌برداری و اتچ اسناد '
            'به‌صورت آنلاین در دسترس است.',
            style: TextStyle(fontSize: 12.5, height: 1.9),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('آدرس شبکه لوکال:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(st.url,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('کد جفت‌سازی (هر بار شروع سرور نو می‌شود):',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(
                    st.pairingCode.isEmpty ? '—' : st.pairingCode,
                    style: const TextStyle(
                        fontSize: 26,
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('گوشی‌های جفت‌شده (${st.devices.length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (st.devices.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('هنوز گوشی‌ای جفت نشده است',
                            style: TextStyle(color: Colors.grey))),
                  for (final d in st.devices)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.smartphone),
                        title: Text(d)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('رویدادها:', style: TextStyle(fontWeight: FontWeight.bold)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (st.log.isEmpty)
                    const Text('—', style: TextStyle(color: Colors.grey)),
                  for (final l in st.log)
                    Text(l, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          Text('${AppInfo.appName} — نسخه ${AppInfo.version}',
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
