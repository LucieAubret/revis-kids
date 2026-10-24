import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/exercise.dart';
import '../../core/curriculum.dart';
import '../../core/quest_theme.dart';
import '../../data/progress.dart';
import '../../ui/fun_background.dart';
import '../../ui/pressable.dart';
import '../../ui/subject_style.dart';
import '../quest/quest_flow_screen.dart';

/// Ouvre un exercice généré sur une notion du programme, dans l'univers choisi.
void startExercise(BuildContext context, Competence c, ExerciseLevel level) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => QuestFlowScreen(competence: c, level: level),
  ));
}

/// Les exercices rangés comme le programme : par matière, puis par section
/// (domaine), puis par notion, avec l'avancement de chaque notion.
class ExercicesScreen extends ConsumerStatefulWidget {
  const ExercicesScreen({super.key, this.matiereId});

  final String? matiereId;

  @override
  ConsumerState<ExercicesScreen> createState() => _ExercicesScreenState();
}

class _ExercicesScreenState extends ConsumerState<ExercicesScreen> {
  String? _matiere;
  ExerciseLevel _level = ExerciseLevel.moyen;

  @override
  void initState() {
    super.initState();
    _matiere = widget.matiereId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(questThemeProvider);
    final curriculum = ref.watch(curriculumProvider);
    final progress = ref.watch(progressProvider).value ?? const ProgressState();

    return Scaffold(
      body: FunBackground(
        theme: theme,
        child: SafeArea(
          child: curriculum.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('Impossible de charger le programme.')),
            data: (c) {
              final selected = c.matiere(_matiere ?? c.matieres.first.id) ?? c.matieres.first;
              return Column(
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
                        Text('Mes exercices', style: Theme.of(context).textTheme.headlineMedium),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          children: [
                            Text(
                              'Choisis une matière, puis une notion du programme de CM1.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 14),
                            _SubjectPicker(
                              curriculum: c,
                              progress: progress,
                              selectedId: selected.id,
                              onSelect: (id) => setState(() => _matiere = id),
                            ),
                            const SizedBox(height: 16),
                            _LevelPicker(
                              level: _level,
                              onChanged: (l) => setState(() => _level = l),
                            ),
                            const SizedBox(height: 8),
                            for (final d in selected.domaines)
                              _DomainSection(
                                domaine: d,
                                matiereId: selected.id,
                                progress: progress,
                                level: _level,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SubjectPicker extends StatelessWidget {
  const _SubjectPicker({
    required this.curriculum,
    required this.progress,
    required this.selectedId,
    required this.onSelect,
  });

  final Curriculum curriculum;
  final ProgressState progress;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in curriculum.matieres)
          _SubjectChip(
            matiere: m,
            acquired: m.competences
                .where((c) => progress.statusOf(c.id) == CompetenceStatus.acquise)
                .length,
            selected: m.id == selectedId,
            onTap: () => onSelect(m.id),
          ),
      ],
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.matiere,
    required this.acquired,
    required this.selected,
    required this.onTap,
  });

  final Matiere matiere;
  final int acquired;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = subjectStyle(matiere.id);
    return Pressable(
      borderRadius: 18,
      shadowColor: style.color,
      selected: selected,
      semanticLabel: matiere.nom,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
        decoration: BoxDecoration(
          color: selected ? style.color : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, color: selected ? Colors.white : style.color, size: 26),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  matiere.nom,
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: selected ? Colors.white : const Color(0xFF241C3A),
                  ),
                ),
                Text(
                  '$acquired / ${matiere.competences.length} acquises',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white70 : const Color(0xFF6B6480),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelPicker extends StatelessWidget {
  const _LevelPicker({required this.level, required this.onChanged});

  final ExerciseLevel level;
  final ValueChanged<ExerciseLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Niveau', style: Theme.of(context).textTheme.titleMedium),
        for (final l in ExerciseLevel.values)
          ChoiceChip(
            label: Text(l.label),
            selected: level == l,
            onSelected: (_) => onChanged(l),
          ),
        Text(level.hint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DomainSection extends StatelessWidget {
  const _DomainSection({
    required this.domaine,
    required this.matiereId,
    required this.progress,
    required this.level,
  });

  final Domaine domaine;
  final String matiereId;
  final ProgressState progress;
  final ExerciseLevel level;

  @override
  Widget build(BuildContext context) {
    final style = subjectStyle(matiereId);
    final acquired = domaine.competences
        .where((c) => progress.statusOf(c.id) == CompetenceStatus.acquise)
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 24, decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(4),
              )),
              const SizedBox(width: 10),
              Expanded(
                child: Text(domaine.nom, style: Theme.of(context).textTheme.titleLarge),
              ),
              Text('$acquired / ${domaine.competences.length}',
                  style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in domaine.competences)
            _CompetenceCard(
              competence: c,
              color: style.color,
              status: progress.statusOf(c.id),
              level: level,
            ),
        ],
      ),
    );
  }
}

class _CompetenceCard extends StatelessWidget {
  const _CompetenceCard({
    required this.competence,
    required this.color,
    required this.status,
    required this.level,
  });

  final Competence competence;
  final Color color;
  final CompetenceStatus status;
  final ExerciseLevel level;

  @override
  Widget build(BuildContext context) {
    final (icon, label, tone) = switch (status) {
      CompetenceStatus.acquise => (Icons.check_circle_rounded, 'Acquise', const Color(0xFF2E7D32)),
      CompetenceStatus.enCours => (Icons.timelapse_rounded, 'En cours', const Color(0xFFEF8F00)),
      CompetenceStatus.nonVue => (Icons.radio_button_unchecked_rounded, 'À découvrir', const Color(0xFF8C86A0)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Pressable(
        borderRadius: 18,
        shadowColor: color,
        semanticLabel: 'S\'entraîner : ${competence.titre}',
        onTap: competence.ecrit
            ? () => startExercise(context, competence, level)
            : () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                content: Text(
                  "Cette notion se travaille à voix haute, avec un adulte : "
                  "il n'y a pas d'exercice écrit pour celle-ci.",
                ),
              )),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon, color: tone, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(competence.titre, style: Theme.of(context).textTheme.titleMedium),
                    Text(label,
                        style: TextStyle(
                            color: tone, fontWeight: FontWeight.w800, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: competence.ecrit ? color : const Color(0xFFE6E2EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      competence.ecrit ? Icons.play_arrow_rounded : Icons.record_voice_over_rounded,
                      color: competence.ecrit ? Colors.white : const Color(0xFF6B6480),
                      size: 20,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      competence.ecrit ? "S'entraîner" : "À l'oral",
                      style: TextStyle(
                        color: competence.ecrit ? Colors.white : const Color(0xFF6B6480),
                        fontWeight: FontWeight.w800,
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
