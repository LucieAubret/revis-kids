import 'package:flutter/material.dart';

import '../core/quest_theme.dart';
import '../game/catalog.dart';
import '../game/game_state.dart';

/// Pastille arrondie avec une icône et une valeur (étoiles, matériaux…).
class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2B2440),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar rond de l'enfant : couleur et personnage choisis dans la boutique.
class AvatarBadge extends StatelessWidget {
  const AvatarBadge({super.key, required this.game, this.size = 64});

  final GameState game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final item = shopItemById(game.avatarId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColors[game.avatarColor],
        border: Border.all(color: Colors.white, width: size * 0.07),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(item.icon, color: Colors.white, size: size * 0.58),
    );
  }
}

/// Barre de niveau : « Niv. 3 » et progression vers le niveau suivant.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.xp, this.width = 150});

  final int xp;
  final double width;

  @override
  Widget build(BuildContext context) {
    final level = levelFor(xp);
    return Semantics(
      label: 'Niveau $level, $xp points d\'expérience',
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Niveau $level',
              style: const TextStyle(
                fontFamily: kHeadingFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2B2440),
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: levelProgress(xp),
                minHeight: 12,
                backgroundColor: Colors.white,
                color: const Color(0xFFFFB400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
