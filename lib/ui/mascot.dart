import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/quest_theme.dart';

/// Mascotte de l'application : Nova, une renarde stylisée aux formes anguleuses,
/// avec son écharpe. Un petit rebond à l'arrivée, un autre au toucher.
class Mascot extends StatefulWidget {
  const Mascot({super.key, this.size = 96, this.scarf = const Color(0xFF2BB6A0)});

  final double size;
  final Color scarf;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Nova, la mascotte',
      child: GestureDetector(
        onTap: () => _c.forward(from: 0),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = Curves.easeOutBack.transform(_c.value);
            return Transform.translate(offset: Offset(0, (1 - t) * 14), child: child);
          },
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(painter: _FoxPainter(widget.scarf)),
          ),
        ),
      ),
    );
  }
}

class _FoxPainter extends CustomPainter {
  _FoxPainter(this.scarf);

  final Color scarf;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Paint fill(Color c) => Paint()..color = c;

    const fur = Color(0xFFE8743B);
    const furDeep = Color(0xFFC4562A);
    const cream = Color(0xFFFFF1E2);
    const ink = Color(0xFF241C3A);

    // Oreilles : triangles hauts, intérieur sombre.
    for (final side in [-1.0, 1.0]) {
      final cx = 50 + side * 25;
      final ear = Path()
        ..moveTo(p(cx - side * 12, 44).dx, p(cx - side * 12, 44).dy)
        ..lineTo(p(cx + side * 4, 4).dx, p(cx + side * 4, 4).dy)
        ..lineTo(p(cx + side * 17, 40).dx, p(cx + side * 17, 40).dy)
        ..close();
      canvas.drawPath(ear, fill(furDeep));
      final inner = Path()
        ..moveTo(p(cx - side * 4, 40).dx, p(cx - side * 4, 40).dy)
        ..lineTo(p(cx + side * 4, 15).dx, p(cx + side * 4, 15).dy)
        ..lineTo(p(cx + side * 11, 38).dx, p(cx + side * 11, 38).dy)
        ..close();
      canvas.drawPath(inner, fill(const Color(0xFF3A2547)));
    }

    // Tête en losange arrondi.
    final head = Path()
      ..moveTo(p(50, 22).dx, p(50, 22).dy)
      ..quadraticBezierTo(p(80, 30).dx, p(80, 30).dy, p(86, 52).dx, p(86, 52).dy)
      ..quadraticBezierTo(p(74, 74).dx, p(74, 74).dy, p(50, 88).dx, p(50, 88).dy)
      ..quadraticBezierTo(p(26, 74).dx, p(26, 74).dy, p(14, 52).dx, p(14, 52).dy)
      ..quadraticBezierTo(p(20, 30).dx, p(20, 30).dy, p(50, 22).dx, p(50, 22).dy)
      ..close();
    canvas.drawPath(head, fill(fur));

    // Masque clair du bas du visage.
    final mask = Path()
      ..moveTo(p(14, 52).dx, p(14, 52).dy)
      ..quadraticBezierTo(p(34, 56).dx, p(34, 56).dy, p(50, 54).dx, p(50, 54).dy)
      ..quadraticBezierTo(p(66, 56).dx, p(66, 56).dy, p(86, 52).dx, p(86, 52).dy)
      ..quadraticBezierTo(p(74, 74).dx, p(74, 74).dy, p(50, 88).dx, p(50, 88).dy)
      ..quadraticBezierTo(p(26, 74).dx, p(26, 74).dy, p(14, 52).dx, p(14, 52).dy)
      ..close();
    canvas.drawPath(mask, fill(cream));

    // Yeux en amande, légèrement relevés, avec un éclat.
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(p(50 + side * 17, 50).dx, p(50 + side * 17, 50).dy);
      canvas.rotate(side * -0.22);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 15 * s, height: 10 * s),
        fill(ink),
      );
      canvas.drawCircle(Offset(-2 * s, -1.6 * s), 1.9 * s, fill(Colors.white));
      canvas.restore();
    }

    // Truffe et petit sourire en coin.
    final nose = Path()
      ..moveTo(p(46, 68).dx, p(46, 68).dy)
      ..lineTo(p(54, 68).dx, p(54, 68).dy)
      ..lineTo(p(50, 73).dx, p(50, 73).dy)
      ..close();
    canvas.drawPath(nose, fill(ink));
    canvas.drawPath(
      Path()
        ..moveTo(p(44, 77).dx, p(44, 77).dy)
        ..quadraticBezierTo(p(50, 81).dx, p(50, 81).dy, p(57, 76).dx, p(57, 76).dy),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * s
        ..strokeCap = StrokeCap.round,
    );

    // Écharpe.
    final band = RRect.fromRectAndRadius(
      Rect.fromLTWH(26 * s, 84 * s, 48 * s, 11 * s),
      Radius.circular(6 * s),
    );
    canvas.drawRRect(band, fill(scarf));
    final tail = Path()
      ..moveTo(p(60, 92).dx, p(60, 92).dy)
      ..lineTo(p(70, 92).dx, p(70, 92).dy)
      ..lineTo(p(68, 104).dx, p(68, 104).dy)
      ..lineTo(p(58, 100).dx, p(58, 100).dy)
      ..close();
    canvas.drawPath(tail, fill(Color.lerp(scarf, Colors.black, 0.18)!));

    // Étincelle près de l'oreille.
    _sparkle(canvas, p(88, 14), 7 * s, fill(const Color(0xFFF6C85F)));
  }

  void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.28;
      final a = -math.pi / 2 + i * math.pi / 4;
      final pt = Offset(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FoxPainter old) => old.scarf != scarf;
}

/// Bulle de dialogue sobre, avec sa petite queue pointée vers la mascotte.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.text, this.maxWidth = 360});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(size: const Size(10, 20), painter: _TailPainter()),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: Color(0xFF241C3A),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width, 1)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height - 1)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
