/// صفحه دستیار هوشمند داخلی — قاعده ۸
library;

import 'package:flutter/material.dart';

import '../../core/services/assistant_service.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final List<_Msg> messages = [
    const _Msg(
      isUser: false,
      text: 'سلام! من دستیار داخلی برنامه هستم و کاملاً آفلاین کار می‌کنم.\n'
          'می‌توانید کارهای روتین را به من بسپارید؛ مثلاً بنویسید:\n'
          '«پرینت فیش شماره RCP-14050904-001» یا «بک‌آپ بگیر» یا «فروش این ماه»',
    ),
  ];
  final inputCtrl = TextEditingController();
  bool busy = false;
  final scrollCtrl = ScrollController();

  @override
  void dispose() {
    inputCtrl.dispose();
    scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = inputCtrl.text.trim();
    if (text.isEmpty || busy) return;
    inputCtrl.clear();
    setState(() {
      messages.add(_Msg(isUser: true, text: text));
      busy = true;
    });
    _scrollDown();
    try {
      final reply = await AssistantService.handle(text);
      if (!mounted) return;
      setState(() {
        messages.add(_Msg(isUser: false, text: reply.text));
        busy = false;
      });
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages.add(_Msg(isUser: false, text: 'خطا در اجرای دستور: $e'));
        busy = false;
      });
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (scrollCtrl.hasClients) {
        scrollCtrl.animateTo(
          scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Text('دستیار هوشمند داخلی', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.green.shade100,
                  label: const Text('آفلاین و بدون نیاز به اینترنت', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: messages.length,
                itemBuilder: (_, i) => _bubble(messages[i]),
              ),
            ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            // دکمه‌های سریع — کارهای روتین پرکاربرد
            Wrap(
              spacing: 6,
              children: [
                for (final q in const [
                  'بک‌آپ بگیر',
                  'یادآوری‌های امروز',
                  'چقدر قابل وصول داریم؟',
                  'فروش این ماه',
                ])
                  ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 11.5)),
                    onPressed: () {
                      inputCtrl.text = q;
                      _send();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputCtrl,
                    decoration: const InputDecoration(
                      hintText: 'دستور خود را بنویسید... مثال: پرینت فیش شماره RCP-14050904-001',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: busy ? null : _send,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('اجرا'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final isUser = m.isUser;
    return Align(
      alignment: isUser ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isUser ? m.text : m.text,
          style: const TextStyle(fontSize: 13, height: 1.8),
        ),
      ),
    );
  }
}

class _Msg {
  final bool isUser;
  final String text;
  const _Msg({required this.isUser, required this.text});
}
