import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quest_theme.dart';
import '../../game/catalog.dart';
import '../../game/game_state.dart';
import '../../game/mastery.dart';
import '../../ui/fun_background.dart';
import '../../ui/game_widgets.dart';

/// Le village de l'enfant : un bâtiment par matière, qui monte de niveau
/// avec des matériaux gagnés ET des notions réellement maîtrisées.
class VillageScreen extends ConsumerWidget {
  const VillageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(questThemeProvider);
    final game = ref.watch(gameProvider).value ?? const GameState();
    final acquired = ref.watch(acquiredByMatiereProvider).value ?? const {};

    return Scaffold(
      body: FunBackground(
        theme: theme,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Retour',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Text('Mon village', style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _DecorStrip(game: game),
                        const SizedBox(height: 14),
                        _MaterialsRow(game: game),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
                            final gap = 16.0;
                            final w = (c.maxWidth - gap * (cols - 1)) / cols;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final b in buildings)
                                  SizedBox(
                                    width: w,
                                    child: _BuildingCard(
                                      building: b,
                                      game: game,
                                      acquired: acquired[b.matiereId] ?? 0,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorStrip extends StatelessWidget {
  const _DecorStrip({required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final decors = shopItems.where((i) => i.kind == ShopKind.decor && game.owns(i.id)).toList();
    return Container(
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF8FD3FF), Color(0xFFD8F1FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 30, color: const Color(0xFF6BC46D)),
            ),
            Center(
              child: decors.isEmpty
                  ? Text(
                      'Gagne des étoiles pour décorer ton village !',
                      style: Theme.of(context).textTheme.titleSmall,
                    )
                  : Wrap(
                      spacing: 18,
                      children: [
                        for (final d in decors)
                          Tooltip(
                            message: d.name,
                            child: Icon(d.icon, size: 46, color: const Color(0xFF2B2440)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialsRow extends StatelessWidget {
  const _MaterialsRow({required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in materials)
          StatPill(
            icon: m.icon,
            label: '${game.materialCount(m.id)}',
            color: m.color,
            semanticLabel: '${game.materialCount(m.id)} ${m.label}',
          ),
      ],
    );
  }
}

class _BuildingCard extends ConsumerWidget {
  const _BuildingCard({
    required this.building,
    required this.game,
    required this.acquired,
  });

  final Building building;
  final GameState game;
  final int acquired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = game.buildingLevel(building.id);
    final maxed = level >= kBuildingMaxLevel;
    final mat = building.material;
    final status = checkUpgrade(game: game, building: building, acquiredInMatiere: acquired);
    final cost = maxed ? 0 : kBuildingCosts[level];
    final needMastery = maxed ? 0 : kBuildingMastery[level];

    Future<void> onBuild() async {
      final messenger = ScaffoldMessenger.of(context);
      final res = await ref
          .read(gameProvider.notifier)
          .upgrade(building, acquiredInMatiere: acquired);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(res == BuildResult.ok
            ? (level == 0
                ? 'Bravo ! Tu as construit : ${building.name} !'
                : '${building.name} passe au niveau ${level + 1} !')
            : 'Pas encore possible.'),
      ));
    }

    final String hint;
    if (maxed) {
      hint = 'Niveau maximum, bravo !';
    } else if (status == BuildResult.needsMastery) {
      hint = 'Maîtrise $needMastery notion(s) de cette matière pour continuer '
          '(tu en as $acquired).';
    } else if (status == BuildResult.notEnoughMaterials) {
      hint = 'Il te manque ${cost - game.materialCount(mat.id)} ${mat.label}.';
    } else {
      hint = 'Tout est prêt !';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: level == 0 ? const Color(0xFFD7D3DE) : building.color,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(building.icon, color: Colors.white, size: 42),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(building.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (var i = 0; i < kBuildingMaxLevel; i++)
                          Icon(
                            i < level ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: const Color(0xFFFFB400),
                            size: 24,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(building.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          if (!maxed)
            Row(
              children: [
                Icon(mat.icon, color: mat.color, size: 22),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('${game.materialCount(mat.id)} / $cost ${mat.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (!maxed)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: status == BuildResult.ok ? onBuild : null,
                child: Text(level == 0 ? 'Construire' : 'Améliorer'),
              ),
            ),
        ],
      ),
    );
  }
}
