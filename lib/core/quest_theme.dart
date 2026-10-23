import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thème d'aventure choisi par l'élève : il habille la quête et l'interface.
enum QuestTheme {
  histoire(
    label: 'Histoire de France',
    tagline: 'Châteaux, rois et chevaliers',
    icon: Icons.castle_rounded,
    seed: Color(0xFFB3472F),
    background: Color(0xFFFFF4E8),
  ),
  danse(
    label: 'Danse classique',
    tagline: 'Scènes, pointes et grands spectacles',
    icon: Icons.music_note_rounded,
    seed: Color(0xFFC2548F),
    background: Color(0xFFFFF0F7),
  ),
  aventures(
    label: 'Aventures',
    tagline: 'Îles, cartes au trésor et expéditions',
    icon: Icons.explore_rounded,
    seed: Color(0xFF1F7A6B),
    background: Color(0xFFEEF9F5),
  );

  const QuestTheme({
    required this.label,
    required this.tagline,
    required this.icon,
    required this.seed,
    required this.background,
  });

  final String label;
  final String tagline;
  final IconData icon;
  final Color seed;
  final Color background;

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, surface: background);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: const Color(0xFF2B2B2B),
        displayColor: const Color(0xFF2B2B2B),
      ),
    );
  }
}

class QuestThemeNotifier extends Notifier<QuestTheme> {
  @override
  QuestTheme build() => QuestTheme.aventures;

  void select(QuestTheme theme) => state = theme;
}

final questThemeProvider =
    NotifierProvider<QuestThemeNotifier, QuestTheme>(QuestThemeNotifier.new);
