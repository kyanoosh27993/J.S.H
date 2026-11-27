/// نمودارهای مدرن تم‌محور — دایره‌ای، خطی، میله‌ای
/// انیمیشن ورود + نمایش راهنما با حرکت موس + ارقام فارسی + فونت اعداد کاربر
library;

import 'package:flutter/material.dart';

import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../widgets/app_text.dart';

class ChartPoint {
  final String label;
  final double value;
  const ChartPoint(this.label, this.value);
}

/// جمع مقادیر همه نقاط — کمک‌تابع برای مرکز دونات و تست‌ها (فاز ۴)
double donutTotal(List<ChartPoint> points) =>
    points.fold<double>(0, (s, e) => s + e.value);

/// ── نمودار دایره‌ای (دونات) ──
class DonutChart extends StatefulWidget {
  final List<ChartPoint> points;
  final String centerLabel;
  final double size;

  /// فاز ۴ — تعامل: تپ روی هر قطاع / مرکز / راهنما
  final ValueChanged<String>? onSegmentTap;
  final VoidCallback? onCenterTap;

  const DonutChart({
    super.key,
    required this.points,
    required this.centerLabel,
    this.size = 220,
    this.onSegmentTap,
    this.onCenterTap,
  });

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int hovered = -1;

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    final colors = p.chartColors;
    final total = donutTotal(widget.points);
    if (total <= 0) {
      return SizedBox(
        height: widget.size,
        child: const Center(child: AppText('داده‌ای برای نمایش نیست')),
      );
    }
    return SizedBox(
      height: widget.size + 64,
      child: Column(
        children: [
          MouseRegion(
            onHover: (e) {
              setState(() => hovered = _segmentAt(e.localPosition, total));
            },
            onExit: (_) => setState(() => hovered = -1),
            // فاز ۴ — تپ روی قطاع‌ها و مرکز دونات
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final hit = _tapTarget(d.localPosition, total);
                if (hit == -1) {
                  widget.onCenterTap?.call();
                } else if (hit >= 0) {
                  widget.onSegmentTap?.call(widget.points[hit].label);
                }
              },
              child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: cfg.animations ? 700 : 0),
              curve: Curves.easeOutCubic,
              builder: (_, t, __) => SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _DonutPainter(
                    points: widget.points,
                    colors: colors,
                    progress: t,
                    hovered: hovered,
                    border: p.border,
                    textPrimary: p.textPrimary,
                    textSecondary: p.textSecondary,
                    numberFont: cfg.effectiveNumberFont,
                    centerLabel: widget.centerLabel,
                  ),
                ),
              ),
            ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < widget.points.length; i++)
                _legend(
                  widget.points[i],
                  colors[i % colors.length],
                  total,
                  hovered: hovered == i,
                  onEnter: () => setState(() => hovered = i),
                  onExit: () => setState(() => hovered = -1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  int _segmentAt(Offset local, double total) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = local - c;
    if (v.distance < widget.size * 0.24) return -1; // وسط دونات
    var angle = _angleOf(v);
    // شروع ترسیم از -90 درجه (بالا) و پیش‌روی ساعتگرد
    var start = -1.5707963;
    for (var i = 0; i < widget.points.length; i++) {
      final sweep =
          6.2831853 * (widget.points[i].value / total) * 1.0;
      if (angle >= start && angle < start + sweep) return i;
      start += sweep;
    }
    return -1;
  }

  /// فاز ۴ — تشخیص هدف تپ: قطاع (>=0)، مرکز (-1)، بیرون حلقه (-2)
  int _tapTarget(Offset local, double total) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = local - c;
    if (v.distance < widget.size * 0.24) return -1; // مرکز دونات
    // شعاع بیرونی حلقه = شعاع ترسیم + نصف ضخامت + تلورانس لمس
    final outer =
        widget.size * 0.42 + widget.size * 0.18 / 2 + 10;
    if (v.distance > outer) return -2;
    return _segmentAt(local, total);
  }

  static double _angleOf(Offset v) {
    var a = v.direction; // -pi..pi با 0 در راست
    if (a < -1.5707963) a += 6.2831853; // یکسان‌سازی با ترسیم ساعتگرد از بالا
    return a;
  }

  Widget _legend(ChartPoint pt, Color color, double total,
      {required bool hovered,
      required VoidCallback onEnter,
      required VoidCallback onExit}) {
    final pct = (pt.value / total * 100).toStringAsFixed(1);
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      // فاز ۴ — راهنما هم تپ‌پذیر است و همان callback قطاع را صدا می‌زند
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSegmentTap?.call(pt.label),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hovered ? color.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 5),
            AppText(pt.label, style: const TextStyle(fontSize: 11.5)),
            const SizedBox(width: 5),
            AppNumText('${toPersianDigits(pct)}٪',
                style: TextStyle(fontSize: 11.5, color: color)),
          ],
        ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<ChartPoint> points;
  final List<Color> colors;
  final double progress;
  final int hovered;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final String numberFont;
  final String centerLabel;

  _DonutPainter({
    required this.points,
    required this.colors,
    required this.progress,
    required this.hovered,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.numberFont,
    required this.centerLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = points.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    final stroke = size.width * 0.18;
    var start = -1.5707963; // از بالا
    for (var i = 0; i < points.length; i++) {
      final sweep =
          6.2831853 * (points[i].value / total) * progress;
      final isHover = hovered == i;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHover ? stroke + 7 : stroke
        ..strokeCap = StrokeCap.butt
        ..color = colors[i % colors.length].withValues(
            alpha: hovered == -1 || isHover ? 1.0 : 0.42);
      canvas.drawArc(Rect.fromCircle(center: c, radius: radius), start, sweep,
          false, paint);
      start += sweep;
    }
    // برچسب مرکز
    final tp = TextPainter(
      text: TextSpan(text: centerLabel,
          style: TextStyle(fontSize: 12.5, color: textSecondary)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height + 6));
    final shown = hovered >= 0 ? points[hovered] : null;
    // فاز ۴ — مرکز دونات باید جمع مقادیر باشد نه تعداد قطاع‌ها
    final valueText = shown != null
        ? money(shown.value.round())
        : money(total.round());
    final tp2 = TextPainter(
      text: TextSpan(
          text: valueText,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textPrimary,
              fontFamily: numberFont)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp2.paint(canvas, c - Offset(tp2.width / 2, -2));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.hovered != hovered ||
      old.points != points;
}

/// ── نمودار خطی ──
class LineChart extends StatefulWidget {
  final List<ChartPoint> points;
  final double height;
  final int dashedFutureFrom; // ایندکس شروع بخش پیش‌بینی (خط‌چین)
  const LineChart({
    super.key,
    required this.points,
    this.height = 230,
    this.dashedFutureFrom = -1,
  });

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  Offset? hoverLocal;

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    if (widget.points.isEmpty) {
      return SizedBox(
          height: widget.height,
          child: const Center(child: AppText('داده‌ای برای نمایش نیست')));
    }
    return MouseRegion(
      onHover: (e) => setState(() => hoverLocal = e.localPosition),
      onExit: (_) => setState(() => hoverLocal = null),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: cfg.animations ? 800 : 0),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => SizedBox(
          height: widget.height,
          child: CustomPaint(
            painter: _LinePainter(
              points: widget.points,
              color: p.primary,
              accent: p.accent,
              grid: p.border,
              textPrimary: p.textPrimary,
              textSecondary: p.textSecondary,
              numberFont: cfg.effectiveNumberFont,
              progress: t,
              dashedFrom: widget.dashedFutureFrom,
              hoverLocal: hoverLocal,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<ChartPoint> points;
  final Color color;
  final Color accent;
  final Color grid;
  final Color textPrimary;
  final Color textSecondary;
  final String numberFont;
  final double progress;
  final int dashedFrom;
  final Offset? hoverLocal;

  _LinePainter({
    required this.points,
    required this.color,
    required this.accent,
    required this.grid,
    required this.textPrimary,
    required this.textSecondary,
    required this.numberFont,
    required this.progress,
    required this.dashedFrom,
    required this.hoverLocal,
  });

  late final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    const double padL = 8.0, padR = 8.0, padT = 26.0, padB = 30.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    maxValue =
        points.fold<double>(0, (s, e) => s + e.value).clamp(1, double.infinity);
    double px(int i) =>
        padL + w * (points.isEmpty ? 0 : i / (points.length - 1).clamp(1, 9999));
    double py(double v) => padT + h * (1 - v / maxValue * 0.92);

    // خطوط شبکه افقی
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.7)
      ..strokeWidth = 0.7;
    for (var g = 0; g <= 3; g++) {
      final y = padT + h * g / 3;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
    }
    // برچسب محور عمودی (ارقام فارسی)
    for (var g = 0; g <= 3; g++) {
      final v = maxValue * (1 - g / 3);
      _label(canvas, shortMoney(v), Offset(padL + 2, padT + h * g / 3 - 4),
          textSecondary, 9.5);
    }

    // مسیر خط با انیمیشن progress
    final fullPts = <Offset>[
      for (var i = 0; i < points.length; i++)
        Offset(px(i), py(points[i].value)),
    ];
    if (fullPts.length == 1) fullPts.add(fullPts.first.translate(1, 0));

    final visibleCount =
        ((fullPts.length - 1) * progress).clamp(0.0, (fullPts.length - 1).toDouble());
    final drawn = <Offset>[fullPts.first];
    for (var i = 1; i < fullPts.length; i++) {
      if (i <= visibleCount) {
        drawn.add(fullPts[i]);
      } else {
        final f = visibleCount - (i - 1);
        if (f > 0) drawn.add(Offset.lerp(fullPts[i - 1], fullPts[i], f)!);
        break;
      }
    }

    // پرکننده گرادیانی زیر خط
    final fillPath = Path()..moveTo(drawn.first.dx, padT + h);
    for (final pt in drawn) {
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(drawn.last.dx, padT + h);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTRB(0, padT, size.width, padT + h)),
    );

    // خط اصلی — بخش پیش‌بینی خط‌چین
    final dashedIdx = dashedFrom < 0
        ? drawn.length
        : dashedFrom.clamp(0, drawn.length);
    final solid = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final dashed = Paint()
      ..color = accent
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < drawn.length - 1; i++) {
      final isFuture = dashedFrom >= 0 && i >= dashedIdx - 1;
      if (!isFuture) {
        canvas.drawLine(drawn[i], drawn[i + 1], solid);
      } else {
        _dashedLine(canvas, drawn[i], drawn[i + 1], dashed);
      }
    }

    // نقاط
    for (var i = 0; i < drawn.length; i++) {
      final dot = Paint()
        ..color = (dashedFrom >= 0 && i >= dashedIdx) ? accent : color;
      canvas.drawCircle(drawn[i], 3.4, dot);
      canvas.drawCircle(drawn[i], 3.4,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.2);
    }

    // برچسب محور افقی
    for (var i = 0; i < points.length; i++) {
      _label(canvas, points[i].label, Offset(px(i), padT + h + 8),
          textSecondary, 9.5, center: true);
    }

    // راهنمای هاور — نزدیک‌ترین نقطه
    if (hoverLocal != null) {
      var best = 0;
      var bestD = double.infinity;
      for (var i = 0; i < drawn.length; i++) {
        final d = (drawn[i] - hoverLocal!).distance;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      if (bestD < 60) {
        final pt = drawn[best];
        canvas.drawLine(
            Offset(pt.dx, padT),
            Offset(pt.dx, padT + h),
            Paint()
              ..color = accent.withValues(alpha: 0.5)
              ..strokeWidth = 1);
        canvas.drawCircle(pt, 5, Paint()..color = accent);
        final text =
            '${points[best].label}: ${money(points[best].value.round())}';
        _tooltip(canvas, text, pt - const Offset(0, 22), textPrimary,
            numberFont, size.width);
      }
    }
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const double dash = 5.0, gap = 4.0;
    final dist = (b - a).distance;
    final dir = (b - a) / dist;
    var t = 0.0;
    while (t < dist) {
      final end = (t + dash).clamp(0.0, dist);
      c.drawLine(a + dir * t, a + dir * end, p);
      t = end + gap;
    }
  }

  void _label(Canvas c, String text, Offset at, Color color, double size,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, color: color, fontFamily: numberFont)),
      textDirection: TextDirection.rtl,
    )..layout();
    var dx = at.dx;
    if (center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, at.dy));
  }

  void _tooltip(Canvas c, String text, Offset at, Color fg, String numFont,
      [double maxW = 400]) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.bold,
              fontFamily: numFont)),
      textDirection: TextDirection.rtl,
    )..layout();
    const pad = 6.0;
    // بند ۸ — کادر تولتیپ داخل مرز نمودار بماند (رفع کادر مستطیل بیرون‌زده در RTL)
    final left = (at.dx - tp.width / 2 - pad).clamp(2.0, maxW - tp.width - pad * 2 - 2.0);
    final rect = Rect.fromLTWH(left, at.dy - pad, tp.width + pad * 2,
        tp.height + pad * 2);
    c.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(7)),
        Paint()..color = Colors.black.withValues(alpha: 0.72));
    tp.paint(c, Offset(rect.left + pad, rect.top + pad));
  }

  String shortMoney(double v) {
    if (v >= 1000000) return '${toPersianDigits((v / 1000000).toStringAsFixed(1))}م';
    if (v >= 1000) return '${toPersianDigits('${(v / 1000).round()}')}ه‌ت';
    return toPersianDigits(v.round().toString());
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.progress != progress || old.hoverLocal != hoverLocal;
}

/// ── نمودار میله‌ای ──
class BarChart extends StatefulWidget {
  final List<ChartPoint> bars;
  final double height;
  const BarChart({super.key, required this.bars, this.height = 230});

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  int hovered = -1;

  @override
  Widget build(BuildContext context) {
    final cfg = AppThemeScope.of(context);
    final p = cfg.palette;
    if (widget.bars.isEmpty) {
      return SizedBox(
          height: widget.height,
          child: const Center(child: AppText('داده‌ای برای نمایش نیست')));
    }
    return MouseRegion(
      onExit: (_) => setState(() => hovered = -1),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: cfg.animations ? 700 : 0),
        curve: Curves.easeOutBack,
        builder: (_, t, __) => SizedBox(
          height: widget.height,
          child: CustomPaint(
            painter: _BarPainter(
              bars: widget.bars,
              colors: p.chartColors,
              border: p.border,
              textPrimary: p.textPrimary,
              textSecondary: p.textSecondary,
              numberFont: cfg.effectiveNumberFont,
              progress: t,
              hovered: hovered,
              onHover: (i) => setState(() => hovered = i),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<ChartPoint> bars;
  final List<Color> colors;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final String numberFont;
  final double progress;
  final int hovered;
  final ValueChanged<int> onHover;

  _BarPainter({
    required this.bars,
    required this.colors,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.numberFont,
    required this.progress,
    required this.hovered,
    required this.onHover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padT = 24.0, padB = 28.0, padX = 6.0;
    final h = size.height - padT - padB;
    final w = (size.width - padX * 2) / bars.length;
    final maxV = bars.fold<double>(0, (s, e) => s + e.value).clamp(1, double.infinity);
    // شبکه
    final grid = Paint()
      ..color = border.withValues(alpha: 0.7)
      ..strokeWidth = 0.7;
    for (var g = 0; g <= 3; g++) {
      final y = padT + h * g / 3;
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), grid);
    }
    for (var i = 0; i < bars.length; i++) {
      final v = bars[i].value;
      final bh = h * (v / maxV) * 0.92 * progress;
      final x = padX + i * w;
      final barW = w * 0.52;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + (w - barW) / 2, padT + h - bh, barW, bh),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      final color = colors[i % colors.length];
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              hovered == i
                  ? Color.lerp(color, Colors.white, 0.35)!
                  : color,
              color.withValues(alpha: 0.55),
            ],
          ).createShader(rect.outerRect),
      );
      // برچسب زیر میله
      final tp = TextPainter(
        text: TextSpan(
            text: bars[i].label,
            style: TextStyle(
                fontSize: 9.5, color: textSecondary)),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas,
          Offset(x + (w - tp.width) / 2, padT + h + 8));
      // مقدار بالای میله (در هاور یا همیشه اگر جا باشد)
      if (hovered == i || bars.length <= 6) {
        final vp = TextPainter(
          text: TextSpan(
              text: toPersianDigits(_short(v)),
              style: TextStyle(
                  fontSize: 9.5,
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                  fontFamily: numberFont)),
          textDirection: TextDirection.rtl,
        )..layout();
        vp.paint(canvas, Offset(x + (w - vp.width) / 2, padT + h - bh - 13));
      }
    }
  }

  String _short(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}م';
    if (v >= 1000) return '${(v / 1000).round()}ه‌ت';
    return v.round().toString();
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.progress != progress || old.hovered != hovered;
}
