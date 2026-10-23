import 'package:flutter/material.dart';

import '../game/catalog.dart';
import '../game/game_state.dart';
import 'game_widgets.dart';

/// Récompenses gagnées : XP, étoiles, matériau, niveau, notion acquise.
class RewardView extends StatelessWidget {
  const RewardView({super.key, required this.reward});

  final Reward reward;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (reward.cappedToday) {
      return Text(
        "Tu as déjà bien travaillé cette notion aujourd'hui. "
        'Reviens demain pour la retenir encore mieux et gagner des récompenses !',
        textAlign: TextAlign.center,
        style: text.titleSmall,
      );
    }
    final material =
        reward.materialId == null ? null : materialById(reward.materialId!);
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            StatPill(
              icon: Icons.bolt_rounded,
              label: '+${reward.xp} XP',
              color: const Color(0xFF7C5CFF),
            ),
            StatPill(
              icon: Icons.star_rounded,
              label: '+${reward.stars}',
              color: const Color(0xFFFFB400),
              semanticLabel: '${reward.stars} étoiles gagnées',
            ),
            if (material != null)
              StatPill(
                icon: material.icon,
                label: '+${reward.materialCount}',
                color: material.color,
                semanticLabel: '${reward.materialCount} ${material.label} gagné(s)',
              ),
          ],
        ),
        if (reward.becameAcquired) ...[
          const SizedBox(height: 12),
          Text('Notion acquise ! Tu la maîtrises vraiment.',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: const Color(0xFF2E7D32))),
        ],
        if (reward.levelUpTo != null) ...[
          const SizedBox(height: 8),
          Text('Niveau ${reward.levelUpTo} atteint !',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: const Color(0xFF7C5CFF))),
        ],
      ],
    );
  }
}
