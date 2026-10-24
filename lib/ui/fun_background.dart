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

    // Grandes formes douces, sans confettis : un fond calme et moderne.
    canvas.drawCircle(Offset(w * 0.95, h * 0.04), w * 0.32, p(theme.gradient.first, 0.16));
    canvas.drawCircle(Offset(w * 0.00, h * 0.45), w * 0.20, p(theme.accent, 0.20));
    canvas.drawCircle(Offset(w * 0.98, h * 0.80), w * 0.26, p(theme.gradient.last, 0.10));

    // Trois petites étincelles discrètes.
    for (final o in [Offset(w * 0.62, h * 0.07), Offset(w * 0.86, h * 0.33), Offset(w * 0.06, h * 0.86)]) {
      _star(canvas, o, 7, p(theme.accent, 0.40));
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
