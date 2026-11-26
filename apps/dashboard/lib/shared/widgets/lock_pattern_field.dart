/// فیلد پترن قفل دستگاه — فاز ۴ (بند ۷)
/// به‌جای محل امضا، کاربر شکل قفل پترن دستگاه را روی شبکه ۳×۳ می‌کشد؛
/// خروجی رشته‌ای مثل «1-5-9-6» ذخیره می‌شود و در PDF با نقاط و خطوط رسم می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/utils.dart';

class LockPatternField extends StatefulWidget {
  final String label;
  final ValueChanged<String> onChanged;
  final String initial;
  const LockPatternField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial = '',
  });

  @override
  State<LockPatternField> createState() => _LockPatternFieldState();
}

class _LockPatternFieldState extends State<LockPatternField> {
  List<int> path = [];

  @override
  void initState() {
    super.initState();
    path = widget.initial
        .split('-')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e >= 1 && e <= 9)
        .toList();
  }

  void _toggle(int n) {
    setState(() {
      if (path.contains(n)) {
        path.remove(n);
      } else {
        path.add(n);
      }
    });
    widget.onChanged(path.join('-'));
  }

  String get display => path.isEmpty
      ? 'ثبت نشده'
      : path.map((e) => toPersianDigits('$e')).join(' → ');

  @override
  Widget build(BuildContext context) {
    const cell = 40.0;
    const gap = 8.0;
    const side = cell * 3 + gap * 2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pattern, size: 18, color: Colors.deepOrange),
                const SizedBox(width: 8),
                Text(widget.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Text(display,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline)),
                IconButton(
                  tooltip: 'پاک کردن پترن',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    setState(() => path.clear());
                    widget.onChanged('');
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: side,
                height: side,
                child: Stack(
                  children: [
                    // خطوط اتصال پترن
                    CustomPaint(
                      size: const Size.square(side),
                      painter: _PatternPainter(path: path, cell: cell, gap: gap),
                    ),
                    // ۹ نقطه
                    for (var row = 0; row < 3; row++)
                      for (var col = 0; col < 3; col++)
                        Positioned(
                          left: col * (cell + gap),
                          top: row * (cell + gap),
                          child: GestureDetector(
                            onTap: () => _toggle(row * 3 + col + 1),
                            child: Container(
                              width: cell,
                              height: cell,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: path.contains(row * 3 + col + 1)
                                    ? Colors.deepOrange.withValues(alpha: 0.25)
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                border: Border.all(
                                  color: path.contains(row * 3 + col + 1)
                                      ? Colors.deepOrange
                                      : Colors.blueGrey.withValues(alpha: 0.4),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                toPersianDigits('${row * 3 + col + 1}'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: path.contains(row * 3 + col + 1)
                                      ? Colors.deepOrange
                                      : Colors.blueGrey,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> path;
  final double cell;
  final double gap;
  const _PatternPainter({required this.path, required this.cell, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;
    Offset center(int n) {
      final row = (n - 1) ~/ 3;
      final col = (n - 1) % 3;
      return Offset(col * (cell + gap) + cell / 2, row * (cell + gap) + cell / 2);
    }

    final paint = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < path.length - 1; i++) {
      canvas.drawLine(center(path[i]), center(path[i + 1]), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.path.toString() != path.toString();
}

/// رسم پترن قفل داخل PDF — نسخه ساده با نقاط و خطوط
class PdfLockPattern {
  /// خروجی: لیست مختصات نسبی (0..1) مراکز نقاط به ترتیب مسیر
  static List<(double, double)> coords(String pattern) {
    final nums = pattern
        .split('-')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e >= 1 && e <= 9)
        .toList();
    return [
      for (final n in nums)
        (
          (((n - 1) % 3) + 0.5) / 3, // ستون
          (((n - 1) ~/ 3) + 0.5) / 3, // ردیف
        ),
    ];
  }
}
