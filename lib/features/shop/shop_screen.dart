import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quest_theme.dart';
import '../../game/catalog.dart';
import '../../game/game_state.dart';
import '../../ui/fun_background.dart';
import '../../ui/game_widgets.dart';
import '../../ui/pressable.dart';

/// Boutique : avatars et décors du village, payés avec les étoiles gagnées.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(questThemeProvider);
    final game = ref.watch(gameProvider).value ?? const GameState();

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
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
                      Text('Boutique', style: Theme.of(context).textTheme.headlineMedium),
                      const Spacer(),
                      StatPill(
                        icon: Icons.star_rounded,
                        label: '${game.stars}',
                        color: const Color(0xFFFFB400),
                        semanticLabel: '${game.stars} étoiles',
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Mon avatar'),
                    Tab(text: 'Décors du village'),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: TabBarView(
                        children: [
                          _AvatarTab(game: game),
                          _ItemGrid(game: game, kind: ShopKind.decor),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarTab extends ConsumerWidget {
  const _AvatarTab({required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: AvatarBadge(game: game, size: 110)),
        const SizedBox(height: 16),
        Text('Couleur', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < avatarColors.length; i++)
              Pressable(
                borderRadius: 30,
                semanticLabel: 'Couleur ${i + 1}',
                selected: game.avatarColor == i,
                onTap: () => ref.read(gameProvider.notifier).selectAvatarColor(i),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: avatarColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: game.avatarColor == i ? const Color(0xFF2B2440) : Colors.white,
                      width: 4,
                    ),
                  ),
                  child: game.avatarColor == i
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Personnage', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _ItemGrid(game: game, kind: ShopKind.avatar, shrink: true),
      ],
    );
  }
}

class _ItemGrid extends ConsumerWidget {
  const _ItemGrid({required this.game, required this.kind, this.shrink = false});

  final GameState game;
  final ShopKind kind;
  final bool shrink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = shopItems.where((i) => i.kind == kind).toList();
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 700 ? 3 : 2;
        return GridView.count(
          shrinkWrap: shrink,
          physics: shrink ? const NeverScrollableScrollPhysics() : null,
          crossAxisCount: cols,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.95,
          padding: shrink ? EdgeInsets.zero : const EdgeInsets.all(16),
          children: [for (final i in items) _ItemCard(item: i, game: game)],
        );
      },
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item, required this.game});

  final ShopItem item;
  final GameState game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = game.owns(item.id);
    final isAvatar = item.kind == ShopKind.avatar;
    final current = isAvatar && game.avatarId == item.id;
    final canAfford = game.stars >= item.price;

    Future<void> onTap() async {
      final notifier = ref.read(gameProvider.notifier);
      final messenger = ScaffoldMessenger.of(context);
      if (owned) {
        if (isAvatar) await notifier.selectAvatar(item.id);
        return;
      }
      final res = await notifier.buy(item);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(switch (res) {
          BuyResult.ok => 'Bravo ! Tu as obtenu « ${item.name} ».',
          BuyResult.notEnoughStars =>
            'Il te manque ${item.price - game.stars} étoile(s). Réussis des défis pour en gagner !',
          BuyResult.alreadyOwned => 'Tu as déjà cet objet.',
        }),
      ));
    }

    return Pressable(
      borderRadius: 28,
      semanticLabel: item.name,
      selected: current,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: current ? const Color(0xFF2FAE66) : Colors.transparent,
            width: 4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: (owned ? avatarColors[game.avatarColor] : const Color(0xFFBDBDBD)),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 10),
            Text(item.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (current)
              const _Tag(text: 'Choisi', color: Color(0xFF2FAE66), icon: Icons.check_rounded)
            else if (owned)
              _Tag(
                text: isAvatar ? 'Choisir' : 'Obtenu',
                color: const Color(0xFF3C8DD9),
                icon: isAvatar ? Icons.touch_app_rounded : Icons.check_rounded,
              )
            else
              _Tag(
                text: '${item.price}',
                color: canAfford ? const Color(0xFFFFB400) : const Color(0xFFB0AAB8),
                icon: Icons.star_rounded,
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }
}
