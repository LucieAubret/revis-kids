import 'package:flutter/material.dart';

import '../core/quest_theme.dart';

/// Mascotte de l'application : Pixel, le renard curieux. Dessinée en vectoriel,
/// elle fait un petit rebond à l'arrivée puis un clin d'œil quand on la touche.
class Mascot extends StatefulWidget {
  const Mascot({super.key, this.size = 150});

  final double size;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  void _wiggle() => _c.forward(from: 0);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pixel, la mascotte',
      child: GestureDetector(
        onTap: _wiggle,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = Curves.elasticOut.transform(_c.value);
            return Transform.translate(
              offset: Offset(0, (1 - t) * 24),
              child: Transform.rotate(angle: (1 - t) * -0.12, child: child),
            );
          },
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(painter: _FoxPainter()),
          ),
        ),
      ),
    );
  }
}

class _FoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint fill(Color c) => Paint()..color = c;

    const orange = Color(0xFFFF8A3D);
    const deep = Color(0xFFE5622A);
    const cream = Color(0xFFFFF3E0);
    const ink = Color(0xFF2B2440);

    // Queue.
    final tail = Path()
      ..moveTo(w * 0.78, h * 0.82)
      ..quadraticBezierTo(w * 1.02, h * 0.78, w * 0.96, h * 0.52)
      ..quadraticBezierTo(w * 0.86, h * 0.66, w * 0.70, h * 0.70)
      ..close();
    canvas.drawPath(tail, fill(deep));
    canvas.drawCircle(Offset(w * 0.955, h * 0.545), w * 0.045, fill(cream));

    // Corps.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.22, h * 0.58, w * 0.56, h * 0.38),
      fill(orange),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * 0.36, h * 0.66, w * 0.28, h * 0.26),
      fill(cream),
    );

    // Oreilles.
    for (final sign in [-1.0, 1.0]) {
      final cx = w * 0.5 + sign * w * 0.24;
      final ear = Path()
        ..moveTo(cx - w * 0.13, h * 0.34)
        ..lineTo(cx + sign * w * 0.05, h * 0.04)
        ..lineTo(cx + w * 0.13, h * 0.34)
        ..close();
      canvas.drawPath(ear, fill(orange));
      final inner = Path()
        ..moveTo(cx - w * 0.06, h * 0.32)
        ..lineTo(cx + sign * w * 0.04, h * 0.12)
        ..lineTo(cx + w * 0.06, h * 0.32)
        ..close();
      canvas.drawPath(inner, fill(const Color(0xFFFFB38A)));
    }

    // Tête.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.14, h * 0.24, w * 0.72, h * 0.54),
      fill(orange),
    );
    // Museau clair.
    final muzzle = Path()
      ..moveTo(w * 0.14, h * 0.58)
      ..quadraticBezierTo(w * 0.5, h * 0.90, w * 0.86, h * 0.58)
      ..quadraticBezierTo(w * 0.5, h * 0.50, w * 0.14, h * 0.58)
      ..close();
    canvas.drawPath(muzzle, fill(cream));

    // Joues.
    for (final sign in [-1.0, 1.0]) {
      canvas.drawCircle(
        Offset(w * 0.5 + sign * w * 0.27, h * 0.62),
        w * 0.05,
        fill(const Color(0xFFFF9E80).withValues(alpha: 0.7)),
      );
    }

    // Yeux brillants.
    for (final sign in [-1.0, 1.0]) {
      final c = Offset(w * 0.5 + sign * w * 0.15, h * 0.50);
      canvas.drawCircle(c, w * 0.062, fill(ink));
      canvas.drawCircle(c.translate(-w * 0.018, -w * 0.02), w * 0.022, fill(Colors.white));
    }

    // Nez et sourire.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.60), width: w * 0.09, height: h * 0.06),
      fill(ink),
    );
    final smile = Path()
      ..moveTo(w * 0.42, h * 0.67)
      ..quadraticBezierTo(w * 0.5, h * 0.74, w * 0.58, h * 0.67);
    canvas.drawPath(
      smile,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.014
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bulle de dialogue de la mascotte, avec sa petite queue pointée vers elle.
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
        CustomPaint(
          size: const Size(16, 28),
          painter: _TailPainter(),
        ),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: Color(0xFF2B2440),
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
      ..moveTo(size.width, 2)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height - 2)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
