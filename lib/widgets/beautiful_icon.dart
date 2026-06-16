import 'package:flutter/material.dart';

class BeautifulIcon extends StatefulWidget {
  final IconData? icon;
  final double? size;
  final Color? color;
  final Color? hoverColor;
  final bool withBackground;

  const BeautifulIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.hoverColor,
    this.withBackground = false,
  });

  @override
  State<BeautifulIcon> createState() => _BeautifulIconState();
}

class _BeautifulIconState extends State<BeautifulIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.icon == null) return const SizedBox.shrink();

    final defaultColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final resolvedColor = widget.color ?? defaultColor;
    final resolvedHoverColor = widget.hoverColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : resolvedColor);
    final currentColor = _hovered ? resolvedHoverColor : resolvedColor;
    final iconWidget = Icon(widget.icon, size: widget.size ?? 24, color: currentColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.withBackground
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: currentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: iconWidget,
            )
          : iconWidget,
    );
  }
}
