import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'demo_mode.dart';

const _demoColor = Color(0xFF7C4DDB);

/// Vrai quand le mode démo est actif.
bool isDemo(WidgetRef ref) => ref.watch(demoModeProvider).value ?? false;

/// Petite pastille « DÉMO » à côté du logo.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _demoColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'DÉMO',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Bandeau de l'accueil : explique le mode démo et permet d'en sortir.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _demoColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _demoColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded, color: _demoColor),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Mode démo : l'IA est simulée, rien n'est envoyé à Google. "
              'Les points de démo sont séparés de ceux de ton enfant.',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(demoModeProvider.notifier).set(false),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
  }
}

/// Propose d'essayer la démo quand la clé n'est pas configurée.
class DemoOfferButton extends ConsumerWidget {
  const DemoOfferButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => ref.read(demoModeProvider.notifier).set(true),
        icon: const Icon(Icons.science_rounded, size: 18),
        label: const Text('Essayer le mode démo (sans clé)'),
        style: TextButton.styleFrom(foregroundColor: _demoColor),
      ),
    );
  }
}

class _Chooser<T extends Enum> extends StatelessWidget {
  const _Chooser({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _demoColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _demoColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13, color: _demoColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in values)
                ChoiceChip(
                  label: Text(label(v)),
                  selected: v == selected,
                  onSelected: (_) => onSelected(v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Démo : choisit ce que « l'IA » répondra à la réponse manuscrite.
class DemoVerdictChooser extends ConsumerWidget {
  const DemoVerdictChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDemo(ref)) return const SizedBox.shrink();
    return _Chooser<DemoVerdict>(
      title: "Démo : l'IA répondra…",
      values: DemoVerdict.values,
      selected: ref.watch(demoVerdictProvider),
      label: (v) => v.label,
      onSelected: ref.read(demoVerdictProvider.notifier).choose,
    );
  }
}

/// Démo : choisit ce que « l'IA » répondra à la dictée écrite.
class DemoDicteeChooser extends ConsumerWidget {
  const DemoDicteeChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDemo(ref)) return const SizedBox.shrink();
    return _Chooser<DemoDictee>(
      title: "Démo : l'IA trouvera…",
      values: DemoDictee.values,
      selected: ref.watch(demoDicteeProvider),
      label: (v) => v.label,
      onSelected: ref.read(demoDicteeProvider.notifier).choose,
    );
  }
}
