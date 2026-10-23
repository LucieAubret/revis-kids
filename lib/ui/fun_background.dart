import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/quest_theme.dart';

/// Fond ludique : aplats colorés doux, grandes formes arrondies et petites
/// étoiles. Il prend les couleurs de l'univers choisi.
class FunBackground extends StatelessWidget {
  const FunBackground({super.key, required this.theme, required this.child});

  final QuestTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          color: theme.background,
        ),
        Positioned.fill(
          child: CustomPaint(painter: _BlobPainter(theme)),
        ),
        child,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.theme);

  final QuestTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint p(Color c, double a) => Paint()..color = c.withValues(alpha: a);

    // Grandes bulles de couleur.
    canvas.drawCircle(Offset(w * 0.92, h * 0.05), w * 0.30, p(theme.gradient.first, 0.20));
    canvas.drawCircle(Offset(w * 0.02, h * 0.38), w * 0.22, p(theme.accent, 0.28));
    canvas.drawCircle(Offset(w * 0.96, h * 0.72), w * 0.26, p(theme.gradient.last, 0.14));
    canvas.drawCircle(Offset(w * 0.10, h * 0.98), w * 0.20, p(theme.gradient.first, 0.16));

    // Petites étoiles et confettis.
    final stars = <Offset>[
      Offset(w * 0.18, h * 0.10),
      Offset(w * 0.55, h * 0.06),
      Offset(w * 0.80, h * 0.30),
      Offset(w * 0.30, h * 0.55),
      Offset(w * 0.68, h * 0.84),
      Offset(w * 0.08, h * 0.80),
    ];
    for (var i = 0; i < stars.length; i++) {
      _star(canvas, stars[i], 9 + (i % 3) * 3, p(theme.accent, 0.55));
    }
    for (final o in [Offset(w * 0.40, h * 0.30), Offset(w * 0.90, h * 0.55), Offset(w * 0.22, h * 0.70)]) {
      canvas.drawCircle(o, 5, p(theme.gradient.last, 0.35));
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.theme != theme;
}
