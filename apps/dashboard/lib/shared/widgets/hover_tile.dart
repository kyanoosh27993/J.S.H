/// کاشی تعاملی — بازخورد بصری حرکت موس روی آیکن‌ها و کارت‌ها (طراحی پویا)
library;

import 'package:flutter/material.dart';

/// هاور: بزرگ‌شدگی ملایم + پس‌زمینه pill + فعال‌سازی با رنگ تاکیدی تم
class HoverTile extends StatefulWidget {
  final Widget child;
  final bool active;
  final double radius;
  final Color hoverColor;
  final Color activeColor;
  final bool animate;
  final VoidCallback? onTap;
  final double hoverScale;

  const HoverTile({
    super.key,
    required this.child,
    this.active = false,
    required this.radius,
    required this.hoverColor,
    required this.activeColor,
    this.animate = true,
    this.onTap,
    this.hoverScale = 1.02,
  });

  @override
  State<HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<HoverTile> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: hovering && widget.animate ? widget.hoverScale : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: widget.active
                  ? widget.activeColor
                  : hovering
                      ? widget.hoverColor
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(widget.radius),
              border: widget.active
                  ? Border.all(
                      color: hovering
                          ? widget.hoverColor
                          : Colors.transparent)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
