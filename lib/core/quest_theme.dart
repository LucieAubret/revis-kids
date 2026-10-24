import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String kHeadingFont = 'Outfit';
const String kBodyFont = 'Nunito';

/// Univers d'aventure choisi par l'élève : il habille l'interface et la quête.
enum QuestTheme {
  histoire(
    label: 'Histoire de France',
    short: 'Chevaliers',
    tagline: 'Châteaux, rois et chevaliers',
    icon: Icons.castle_rounded,
    seed: Color(0xFFB8402C),
    background: Color(0xFFFBF1E6),
    gradient: [Color(0xFFE0703C), Color(0xFF9C2F3F)],
    accent: Color(0xFFF2B84B),
  ),
  danse(
    label: 'Danse classique',
    tagline: 'Scène, rideaux et grands spectacles',
    short: 'Scène',
    icon: Icons.theater_comedy_rounded,
    seed: Color(0xFFB83A8E),
    background: Color(0xFFF8EEF8),
    gradient: [Color(0xFFE45A9B), Color(0xFF6C3BC4)],
    accent: Color(0xFFF6C85F),
  ),
  aventures(
    label: 'Aventures',
    tagline: 'Îles, cartes au trésor et expéditions',
    short: 'Trésors',
    icon: Icons.map_rounded,
    seed: Color(0xFF0F8A78),
    background: Color(0xFFE8F4F1),
    gradient: [Color(0xFF2BB6A0), Color(0xFF1A6FA8)],
    accent: Color(0xFFF0A93B),
  );

  const QuestTheme({
    required this.label,
    required this.short,
    required this.tagline,
    required this.icon,
    required this.seed,
    required this.background,
    required this.gradient,
    required this.accent,
  });

  final String label;
  final String short;
  final String tagline;
  final IconData icon;
  final Color seed;
  final Color background;
  final List<Color> gradient;
  final Color accent;

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      surface: background,
    ).copyWith(primary: seed);
    const ink = Color(0xFF2B2440);

    TextStyle heading(double size, {double? height}) => TextStyle(
          fontFamily: kHeadingFont,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: height ?? 1.15,
          color: ink,
        );
    TextStyle body(double size, {FontWeight? weight}) => TextStyle(
          fontFamily: kBodyFont,
          fontSize: size,
          fontWeight: weight ?? FontWeight.w500,
          height: 1.35,
          color: ink,
        );

    final textTheme = TextTheme(
      displayLarge: heading(48),
      displayMedium: heading(40),
      displaySmall: heading(34),
      headlineLarge: heading(30),
      headlineMedium: heading(26),
      headlineSmall: heading(22),
      titleLarge: heading(21),
      titleMedium: body(18, weight: FontWeight.w700),
      titleSmall: body(16, weight: FontWeight.w700),
      bodyLarge: body(18),
      bodyMedium: body(16),
      bodySmall: body(14),
      labelLarge: body(16, weight: FontWeight.w800),
      labelMedium: body(14, weight: FontWeight.w700),
      labelSmall: body(12, weight: FontWeight.w700),
    );

    const radius = BorderRadius.all(Radius.circular(20));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: kBodyFont,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: heading(22),
        foregroundColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: body(18, weight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          side: BorderSide(color: seed, width: 2),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: body(17, weight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: heading(18),
        unselectedLabelStyle: heading(18),
        labelColor: seed,
        unselectedLabelColor: ink.withValues(alpha: 0.65),
        indicatorColor: seed,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        labelStyle: body(15, weight: FontWeight.w700),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
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
