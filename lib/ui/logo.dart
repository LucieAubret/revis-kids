import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/quest_theme.dart';

/// Logo de l'application : un médaillon dégradé avec un « R » et une étincelle,
/// suivi du nom. Sobre et moderne, loin d'un style « bébé ».
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.theme, this.size = 36, this.showName = true});

  final QuestTheme theme;
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Revis',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.32),
              gradient: LinearGradient(
                colors: theme.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.gradient.last.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'R',
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: size * 0.62,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
                Positioned(
                  right: size * 0.1,
                  top: size * 0.08,
                  child: CustomPaint(
                    size: Size(size * 0.26, size * 0.26),
                    painter: _SparklePainter(theme.accent),
                  ),
                ),
              ],
            ),
          ),
          if (showName) ...[
            const SizedBox(width: 10),
            Text(
              'Revis',
              style: TextStyle(
                fontFamily: kHeadingFont,
                fontSize: size * 0.66,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: const Color(0xFF241C3A),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.seed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'CM1',
                style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800,
                  color: theme.seed,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.28;
      final a = -math.pi / 2 + i * math.pi / 4;
      final pt = Offset(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}
