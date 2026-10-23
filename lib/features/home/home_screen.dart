import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quest_theme.dart';
import '../../game/catalog.dart';
import '../../game/game_state.dart';
import '../../ui/fun_background.dart';
import '../../ui/game_widgets.dart';
import '../../ui/mascot.dart';
import '../../ui/pressable.dart';
import '../../ui/universe_art.dart';
import '../dictee/dictee_screen.dart';
import '../parent/parent_gate.dart';
import '../scan/scan_screen.dart';
import '../shop/shop_screen.dart';
import '../village/village_screen.dart';

const _ink = Color(0xFF2B2440);

void _open(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(questThemeProvider);
    final game = ref.watch(gameProvider).value ?? const GameState();

    return Scaffold(
      body: FunBackground(
        theme: theme,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 12, wide ? 32 : 16, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(game: game, wide: wide),
                        const SizedBox(height: 20),
                        wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(flex: 5, child: _MascotHero()),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    flex: 4,
                                    child: _ScanButton(theme: theme),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  const _MascotHero(),
                                  const SizedBox(height: 20),
                                  _ScanButton(theme: theme),
                                ],
                              ),
                        const SizedBox(height: 32),
                        Text(
                          'Choisis ton univers',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 14),
                        _UniverseRow(selected: theme, wide: wide),
                        const SizedBox(height: 28),
                        _Shortcuts(game: game, wide: wide),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.game, required this.wide});

  final GameState game;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Pressable(
          borderRadius: 40,
          semanticLabel: 'Mon avatar',
          onTap: () => _open(context, const ShopScreen(initialTab: 0)),
          child: AvatarBadge(game: game, size: wide ? 72 : 60),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LevelBar(xp: game.xp, width: wide ? 160 : 110),
              Pressable(
                borderRadius: 40,
                semanticLabel: 'Mes étoiles : ${game.stars}',
                onTap: () => _open(context, const ShopScreen()),
                child: StatPill(
                  icon: Icons.star_rounded,
                  label: '${game.stars}',
                  color: const Color(0xFFFFB400),
                  semanticLabel: '${game.stars} étoiles',
                ),
              ),
            ],
          ),
        ),
        // Accès parent : discret, protégé par un code PIN.
        Tooltip(
          message: 'Espace parent',
          child: TextButton.icon(
            onPressed: () => _open(context, const ParentGate()),
            icon: const Icon(Icons.lock_outline_rounded, size: 20),
            label: wide ? const Text('Espace parent') : const SizedBox.shrink(),
            style: TextButton.styleFrom(
              foregroundColor: _ink.withValues(alpha: 0.55),
              shape: const StadiumBorder(),
              padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 10, vertical: 10),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _MascotHero extends StatelessWidget {
  const _MascotHero();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Mascot(size: 150),
        SizedBox(width: 4),
        Flexible(child: SpeechBubble(text: 'Prêt pour ta mission du jour ?', maxWidth: 460)),
      ],
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.theme});

  final QuestTheme theme;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      borderRadius: 36,
      shadowColor: theme.gradient.last,
      semanticLabel: 'Scanner mon devoir',
      onTap: () => _open(context, const ScanScreen()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.photo_camera_rounded, size: 40, color: theme.gradient.last),
            ),
            const SizedBox(width: 18),
            const Flexible(
              child: Text(
                'Scanner mon devoir',
                style: TextStyle(
                  fontFamily: kHeadingFont,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UniverseRow extends ConsumerWidget {
  const _UniverseRow({required this.selected, required this.wide});

  final QuestTheme selected;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void choose(QuestTheme t) => ref.read(questThemeProvider.notifier).select(t);
    final cards = [
      for (final t in QuestTheme.values)
        _UniverseCard(theme: t, selected: t == selected, onTap: () => choose(t)),
    ];
    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 20),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          cards[i],
        ],
      ],
    );
  }
}

class _UniverseCard extends StatelessWidget {
  const _UniverseCard({required this.theme, required this.selected, required this.onTap});

  final QuestTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      borderRadius: 32,
      shadowColor: theme.gradient.last,
      selected: selected,
      semanticLabel: theme.label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 5,
          ),
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Stack(
            children: [
              Positioned.fill(child: UniverseArt(theme: theme)),
              Positioned(
                left: 18,
                top: 16,
                right: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            theme.label,
                            style: const TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              color: Colors.white,
                              shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            theme.tagline,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 18, color: theme.gradient.last),
                            const SizedBox(width: 4),
                            Text('Choisi',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: theme.gradient.last,
                                )),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.game, required this.wide});

  final GameState game;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final built = game.buildingLevels.values.fold<int>(0, (a, b) => a + b);
    final total = buildings.length * kBuildingMaxLevel;
    final tiles = [
      _ShortcutTile(
        icon: Icons.holiday_village_rounded,
        color: const Color(0xFF2FAE66),
        title: 'Mon village',
        subtitle: '$built / $total niveaux construits',
        onTap: () => _open(context, const VillageScreen()),
      ),
      _ShortcutTile(
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF7C5CFF),
        title: 'Dictée magique',
        subtitle: 'Écoute, écris, corrige',
        onTap: () => _open(context, const DicteeScreen()),
      ),
      _ShortcutTile(
        icon: Icons.storefront_rounded,
        color: const Color(0xFFFF8A3D),
        title: 'Boutique',
        subtitle: '${game.stars} étoile(s) à dépenser',
        onTap: () => _open(context, const ShopScreen()),
      ),
    ];
    return wide
        ? Row(children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              Expanded(child: tiles[i]),
            ],
          ])
        : Column(children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              tiles[i],
            ],
          ]);
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      borderRadius: 28,
      semanticLabel: title,
      onTap: onTap,
      shadowColor: color,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _ink.withValues(alpha: 0.4), size: 30),
          ],
        ),
      ),
    );
  }
}
