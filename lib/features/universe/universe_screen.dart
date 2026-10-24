import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/exercise.dart';
import '../../core/curriculum.dart';
import '../../core/quest_theme.dart';
import '../../core/universe_missions.dart';
import '../../data/progress.dart';
import '../../ui/fun_background.dart';
import '../../ui/pressable.dart';
import '../../ui/subject_style.dart';
import '../../ui/universe_art.dart';
import '../exercices/exercices_screen.dart';

/// Page d'un univers : l'histoire d'introduction, puis des missions choisies
/// dans le programme, mises en scène dans cet univers.
class UniverseScreen extends ConsumerWidget {
  const UniverseScreen({super.key, required this.theme});

  final QuestTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = universes[theme]!;
    final curriculum = ref.watch(curriculumProvider).value;
    final progress = ref.watch(progressProvider).value ?? const ProgressState();

    return Theme(
      data: theme.toThemeData(),
      child: Scaffold(
        body: FunBackground(
          theme: theme,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Retour',
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                    _Cover(theme: theme),
                    const SizedBox(height: 16),
                    Text(info.pitch, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 22),
                    Text('Tes missions', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Chaque mission est un exercice du programme de CM1, '
                      "raconté dans l'univers « ${theme.label} ».",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    if (curriculum == null)
                      const Center(child: CircularProgressIndicator())
                    else
                      for (final m in info.missions)
                        if (curriculum.competence(m.competenceId) != null)
                          _MissionCard(
                            mission: m,
                            competence: curriculum.competence(m.competenceId)!,
                            status: progress.statusOf(m.competenceId),
                            theme: theme,
                          ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const ExercicesScreen(),
                      )),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('Voir tout le programme par matière'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.theme});

  final QuestTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: theme.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.gradient.last.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned.fill(child: UniverseArt(theme: theme)),
            Positioned(
              left: 20,
              top: 18,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.label,
                    style: const TextStyle(
                      fontFamily: kHeadingFont,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)],
                    ),
                  ),
                  Text(
                    theme.tagline,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)],
                    ),
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

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.competence,
    required this.status,
    required this.theme,
  });

  final UniverseMission mission;
  final Competence competence;
  final CompetenceStatus status;
  final QuestTheme theme;

  @override
  Widget build(BuildContext context) {
    final style = subjectStyle(competence.matiereId);
    final done = status == CompetenceStatus.acquise;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Pressable(
        borderRadius: 20,
        shadowColor: style.color,
        semanticLabel: 'Mission : ${mission.hook}',
        onTap: () => startExercise(context, competence, ExerciseLevel.moyen),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: style.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(style.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mission.hook, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      competence.titre,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                done ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                color: done ? const Color(0xFF2E7D32) : theme.seed,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
