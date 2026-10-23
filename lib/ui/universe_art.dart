import 'package:flutter/material.dart';

import '../core/quest_theme.dart';

/// Illustration vectorielle d'un univers, dessinée dans la carte de quête.
class UniverseArt extends StatelessWidget {
  const UniverseArt({super.key, required this.theme});

  final QuestTheme theme;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: switch (theme) {
        QuestTheme.histoire => _CastlePainter(),
        QuestTheme.danse => _StagePainter(),
        QuestTheme.aventures => _TreasureMapPainter(),
      },
      size: Size.infinite,
    );
  }
}

Paint _fill(Color c) => Paint()..color = c;

Paint _stroke(Color c, double width) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round;

/// Chevaliers : colline verte, château à créneaux, drapeau et soleil.
class _CastlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    canvas.drawCircle(Offset(w * 0.86, h * 0.26), h * 0.15, _fill(const Color(0xFFFFE27A)));

    final hill = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.80)
      ..quadraticBezierTo(w * 0.45, h * 0.58, w, h * 0.82)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hill, _fill(const Color(0xFF6BC46D)));

    const stone = Color(0xFFF3E6D3);
    const shade = Color(0xFFD9C4A6);
    final baseX = w * 0.50;
    final baseW = w * 0.30;
    final top = h * 0.44;
    canvas.drawRect(Rect.fromLTWH(baseX, top, baseW, h * 0.40), _fill(stone));
    // Tours.
    for (final x in [baseX - w * 0.04, baseX + baseW - w * 0.05]) {
      canvas.drawRect(Rect.fromLTWH(x, top - h * 0.12, w * 0.09, h * 0.52), _fill(shade));
      final roof = Path()
        ..moveTo(x - w * 0.012, top - h * 0.12)
        ..lineTo(x + w * 0.045, top - h * 0.30)
        ..lineTo(x + w * 0.102, top - h * 0.12)
        ..close();
      canvas.drawPath(roof, _fill(const Color(0xFFE2493B)));
    }
    // Créneaux.
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(baseX + i * baseW / 4 + 3, top - h * 0.06, baseW / 4 - 8, h * 0.06),
        _fill(stone),
      );
    }
    // Porte.
    final door = Path()
      ..moveTo(baseX + baseW * 0.38, h * 0.84)
      ..lineTo(baseX + baseW * 0.38, h * 0.68)
      ..arcToPoint(Offset(baseX + baseW * 0.62, h * 0.68), radius: Radius.circular(baseW * 0.12))
      ..lineTo(baseX + baseW * 0.62, h * 0.84)
      ..close();
    canvas.drawPath(door, _fill(const Color(0xFF8A5A3B)));
    // Drapeau.
    final mastX = baseX + w * 0.005 + w * 0.04;
    canvas.drawLine(Offset(mastX, top - h * 0.30), Offset(mastX, top - h * 0.46), _stroke(const Color(0xFF5B4636), 3));
    final flag = Path()
      ..moveTo(mastX, top - h * 0.46)
      ..lineTo(mastX + w * 0.07, top - h * 0.42)
      ..lineTo(mastX, top - h * 0.38)
      ..close();
    canvas.drawPath(flag, _fill(const Color(0xFFFFC93C)));
    // Bouclier de chevalier au premier plan.
    final shield = Path()
      ..moveTo(w * 0.14, h * 0.52)
      ..lineTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.30, h * 0.68)
      ..quadraticBezierTo(w * 0.30, h * 0.82, w * 0.22, h * 0.88)
      ..quadraticBezierTo(w * 0.14, h * 0.82, w * 0.14, h * 0.68)
      ..close();
    canvas.drawPath(shield, _fill(const Color(0xFF3B5BDB)));
    canvas.drawLine(Offset(w * 0.22, h * 0.54), Offset(w * 0.22, h * 0.86), _stroke(const Color(0xFFFFE27A), 5));
    canvas.drawLine(Offset(w * 0.15, h * 0.64), Offset(w * 0.29, h * 0.64), _stroke(const Color(0xFFFFE27A), 5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Scène : rideaux rouges, projecteur et petite danseuse sur les pointes.
class _StagePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    // Projecteur.
    final beam = Path()
      ..moveTo(w * 0.62, 0)
      ..lineTo(w * 0.80, 0)
      ..lineTo(w * 0.92, h * 0.92)
      ..lineTo(w * 0.50, h * 0.92)
      ..close();
    canvas.drawPath(beam, _fill(Colors.white.withValues(alpha: 0.30)));

    // Plancher de scène.
    canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14), _fill(const Color(0xFFB8672F)));

    // Rideaux.
    for (final left in [true, false]) {
      final x = left ? 0.0 : w;
      final dir = left ? 1.0 : -1.0;
      final curtain = Path()
        ..moveTo(x, 0)
        ..lineTo(x + dir * w * 0.26, 0)
        ..quadraticBezierTo(x + dir * w * 0.12, h * 0.45, x + dir * w * 0.20, h * 0.90)
        ..lineTo(x, h * 0.90)
        ..close();
      canvas.drawPath(curtain, _fill(const Color(0xFFD62F4B)));
      canvas.drawPath(
        Path()
          ..moveTo(x + dir * w * 0.09, 0)
          ..quadraticBezierTo(x + dir * w * 0.04, h * 0.45, x + dir * w * 0.09, h * 0.90),
        _stroke(const Color(0xFF9E1B34), 3),
      );
    }

    // Danseuse.
    final cx = w * 0.70;
    final base = h * 0.84;
    canvas.drawCircle(Offset(cx, base - h * 0.50), h * 0.065, _fill(const Color(0xFFFFD3B0)));
    canvas.drawCircle(Offset(cx, base - h * 0.575), h * 0.035, _fill(const Color(0xFF5B3A29)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, base - h * 0.37), width: h * 0.10, height: h * 0.18),
        const Radius.circular(10),
      ),
      _fill(const Color(0xFFFFFFFF)),
    );
    // Tutu.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, base - h * 0.27), width: h * 0.36, height: h * 0.10),
      _fill(const Color(0xFFFFB3D9)),
    );
    // Jambes et bras.
    canvas.drawLine(Offset(cx - h * 0.03, base - h * 0.24), Offset(cx - h * 0.03, base), _stroke(const Color(0xFFFFD3B0), 5));
    canvas.drawLine(Offset(cx + h * 0.03, base - h * 0.24), Offset(cx + h * 0.10, base - h * 0.10), _stroke(const Color(0xFFFFD3B0), 5));
    canvas.drawLine(Offset(cx - h * 0.04, base - h * 0.43), Offset(cx - h * 0.17, base - h * 0.58), _stroke(const Color(0xFFFFD3B0), 5));
    canvas.drawLine(Offset(cx + h * 0.04, base - h * 0.43), Offset(cx + h * 0.17, base - h * 0.58), _stroke(const Color(0xFFFFD3B0), 5));

    // Notes de musique.
    for (final o in [Offset(w * 0.34, h * 0.62), Offset(w * 0.44, h * 0.74)]) {
      canvas.drawCircle(o, 7, _fill(Colors.white));
      canvas.drawLine(o.translate(6, 0), o.translate(6, -26), _stroke(Colors.white, 3));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Carte au trésor : parchemin, chemin en pointillés, île avec palmier, croix.
class _TreasureMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    // Mer et île.
    canvas.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38), _fill(const Color(0xFF39A8E0).withValues(alpha: 0.85)));
    for (var i = 0; i < 4; i++) {
      final y = h * (0.72 + i * 0.07);
      final wave = Path()..moveTo(w * 0.05 + i * 12, y);
      for (var k = 0; k < 5; k++) {
        wave.relativeQuadraticBezierTo(8, -6, 16, 0);
      }
      canvas.drawPath(wave, _stroke(Colors.white.withValues(alpha: 0.6), 2.5));
    }
    canvas.drawOval(
      Rect.fromLTWH(w * 0.46, h * 0.50, w * 0.46, h * 0.26),
      _fill(const Color(0xFFF2D37A)),
    );
    // Palmier.
    canvas.drawLine(Offset(w * 0.78, h * 0.58), Offset(w * 0.74, h * 0.26), _stroke(const Color(0xFF8A5A3B), 6));
    for (final a in [-1.0, -0.4, 0.3, 1.0]) {
      final leaf = Path()
        ..moveTo(w * 0.74, h * 0.27)
        ..quadraticBezierTo(w * 0.74 + a * w * 0.12, h * 0.14, w * 0.74 + a * w * 0.17, h * 0.30);
      canvas.drawPath(leaf, _stroke(const Color(0xFF2E9E5B), 7));
    }
    // Chemin en pointillés.
    final route = Path()
      ..moveTo(w * 0.08, h * 0.34)
      ..quadraticBezierTo(w * 0.25, h * 0.10, w * 0.34, h * 0.40)
      ..quadraticBezierTo(w * 0.40, h * 0.62, w * 0.56, h * 0.60);
    for (final m in route.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 16) {
        canvas.drawPath(m.extractPath(d, d + 8), _stroke(const Color(0xFF7A3E1D), 4));
      }
    }
    // Croix du trésor.
    final cx = w * 0.60;
    final cy = h * 0.62;
    canvas.drawLine(Offset(cx - 11, cy - 11), Offset(cx + 11, cy + 11), _stroke(const Color(0xFFD62F2F), 6));
    canvas.drawLine(Offset(cx + 11, cy - 11), Offset(cx - 11, cy + 11), _stroke(const Color(0xFFD62F2F), 6));
    // Coffre.
    final chest = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.56, w * 0.20, h * 0.18),
      const Radius.circular(8),
    );
    canvas.drawRRect(chest, _fill(const Color(0xFF9A5B2E)));
    canvas.drawRect(Rect.fromLTWH(w * 0.08, h * 0.56, w * 0.20, h * 0.05), _fill(const Color(0xFFFFC93C)));
    canvas.drawCircle(Offset(w * 0.18, h * 0.66), 5, _fill(const Color(0xFFFFC93C)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
