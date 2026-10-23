import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quest_theme.dart';
import '../scan/scan_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(questThemeProvider);
    final scheme = Theme.of(context).colorScheme;

    final hero = _Hero(theme: theme);
    final picker = _ThemePicker(
      selected: theme,
      onSelect: (t) => ref.read(questThemeProvider.notifier).select(t),
    );
    final scanButton = _ScanButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [hero, const SizedBox(height: 32), scanButton],
                              ),
                            ),
                            const SizedBox(width: 48),
                            Expanded(child: picker),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            hero,
                            const SizedBox(height: 24),
                            picker,
                            const SizedBox(height: 24),
                            scanButton,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
      backgroundColor: scheme.surface,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.theme});

  final QuestTheme theme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(theme.icon, size: 40, color: scheme.primary),
            const SizedBox(width: 12),
            Text(
              "Revis'Kids",
              style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Salut ! Prêt pour une nouvelle quête ?',
          style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'Prends ton devoir en photo : je le transforme en défi. '
          'Tu écris ta réponse sur ton cahier, puis tu me la montre.',
          style: text.titleMedium,
        ),
      ],
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.selected, required this.onSelect});

  final QuestTheme selected;
  final ValueChanged<QuestTheme> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Choisis ton univers",
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final t in QuestTheme.values) ...[
          _ThemeCard(
            theme: t,
            selected: t == selected,
            onTap: () => onSelect(t),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final QuestTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: theme.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? theme.seed : Colors.transparent,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.seed.withValues(alpha: 0.15),
                child: Icon(theme.icon, color: theme.seed, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.label,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(theme.tagline, style: text.bodyMedium),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: theme.seed),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.camera_alt_rounded, size: 32),
        label: const Text('Scanner mon devoir'),
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }
}
