import 'package:flutter/material.dart';

/// The project-wide Piki mark. Keeping cropping, rounding, semantics, and the
/// code-drawn fallback in one place prevents the brand from drifting between
/// splash, authentication, navigation, and receipt flows.
class PikiMark extends StatelessWidget {
  static const assetPath = 'assets/images/piki_mark_v2.png';

  final double size;
  final double? radius;
  final bool showShadow;

  const PikiMark({
    super.key,
    this.size = 48,
    this.radius,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final corner = radius ?? size * 0.23;
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => SizedBox.square(
          dimension: size,
          child: const CustomPaint(painter: _PikiFallbackPainter()),
        ),
      ),
    );

    return Semantics(
      image: true,
      label: 'Piki',
      child: showShadow
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(corner),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0B1020).withValues(alpha: 0.24),
                    blurRadius: size * 0.34,
                    offset: Offset(0, size * 0.12),
                  ),
                ],
              ),
              child: mark,
            )
          : mark,
    );
  }
}

class _PikiFallbackPainter extends CustomPainter {
  const _PikiFallbackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final tile = Paint()..color = const Color(0xFF0B1020);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.23),
      ),
      tile,
    );

    final stroke = Paint()
      ..color = const Color(0xFFFF5C52)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.16;
    final loop = Path()
      ..moveTo(size.width * 0.34, size.height * 0.76)
      ..lineTo(size.width * 0.34, size.height * 0.34)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.18,
        size.width * 0.72,
        size.height * 0.18,
        size.width * 0.72,
        size.height * 0.43,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.68,
        size.width * 0.42,
        size.height * 0.68,
        size.width * 0.34,
        size.height * 0.58,
      );
    canvas.drawPath(loop, stroke);

    final signal = Paint()..color = const Color(0xFF2DD4BF);
    canvas.drawCircle(
      Offset(size.width * 0.73, size.height * 0.63),
      size.width * 0.055,
      signal,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
