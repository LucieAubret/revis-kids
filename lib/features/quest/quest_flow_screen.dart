import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/exercise.dart';
import '../../ai/gemini_client.dart';
import '../../ai/prompt.dart';
import '../../ai/quest.dart';
import '../../core/curriculum.dart';
import '../../core/quest_theme.dart';
import '../../data/progress.dart';
import '../tutor/answer_flow_screen.dart';

enum _Phase { loading, error, notExercise, confirm, quest }

/// De la photo du devoir à la quête : analyse, confirmation en cas de doute,
/// puis défi scénarisé à écrire sur le cahier.
class QuestFlowScreen extends ConsumerStatefulWidget {
  const QuestFlowScreen({
    super.key,
    this.photo,
    this.mimeType,
    this.note,
    this.competence,
    this.level = ExerciseLevel.moyen,
  });

  /// Photo de l'exercice. Sans photo, la description écrite ou dictée suffit.
  final Uint8List? photo;
  final String? mimeType;

  /// Notion choisie dans le programme : l'IA invente alors un exercice dessus.
  final Competence? competence;
  final ExerciseLevel level;

  /// Précision de l'élève sur l'exercice à traiter (peut être vide).
  final String? note;

  @override
  ConsumerState<QuestFlowScreen> createState() => _QuestFlowScreenState();
}

class _QuestFlowScreenState extends ConsumerState<QuestFlowScreen> {
  _Phase _phase = _Phase.loading;
  Quest? _quest;
  String? _errorMessage;
  bool _canRetry = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
    });
    try {
      final theme = ref.read(questThemeProvider);
      final competence = widget.competence;
      if (competence != null) {
        final service = await ref.read(exerciseServiceProvider.future);
        _quest = await service.generateExercise(
          competence: competence,
          theme: theme,
          level: widget.level,
        );
        if (!mounted) return;
        await _showQuest();
        return;
      }
      final curriculum = await ref.read(curriculumProvider.future);
      final generator = await ref.read(questGeneratorProvider.future);
      final result = await generator.createQuest(
        image: widget.photo,
        mimeType: widget.mimeType,
        theme: theme,
        curriculum: curriculum,
        note: widget.note,
      );
      if (!mounted) return;
      if (!result.isExercise) {
        setState(() => _phase = _Phase.notExercise);
        return;
      }
      _quest = result.quest;
      if (_quest!.needsConfirmation) {
        setState(() => _phase = _Phase.confirm);
      } else {
        await _showQuest();
      }
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.childMessage;
        _canRetry = e.kind != GeminiErrorKind.noKey && e.kind != GeminiErrorKind.auth;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = "Oups, je n'ai pas réussi à analyser ton exercice. Réessaie !";
        _canRetry = true;
      });
    }
  }

  Future<void> _showQuest() async {
    final quest = _quest!;
    final theme = ref.read(questThemeProvider);
    final now = DateTime.now();
    await ref.read(progressProvider.notifier).addScan(ScanRecord(
          id: now.microsecondsSinceEpoch.toString(),
          date: now,
          themeLabel: theme.label,
          matiereId: quest.matiereId,
          competenceId: quest.competenceId,
          note: cleanNote(widget.note),
          kind: widget.competence != null ? kindExercice : kindDevoir,
        ));
    if (!mounted) return;
    setState(() => _phase = _Phase.quest);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.competence != null ? 'Mon exercice' : 'Ma recherche'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: switch (_phase) {
                _Phase.loading => _Loading(
                    text: widget.competence != null
                        ? 'Je prépare ton exercice…'
                        : 'Je cherche ton exercice…',
                  ),
                _Phase.error => _Message(
                    icon: Icons.cloud_off_rounded,
                    text: _errorMessage ?? '',
                    actionLabel: _canRetry ? 'Réessayer' : null,
                    onAction: _run,
                  ),
                _Phase.notExercise => _Message(
                    icon: Icons.search_off_rounded,
                    text: widget.photo == null
                        ? "Je n'ai pas bien compris cet exercice. Ajoute des détails "
                            'ou une photo, puis réessaie.'
                        : "Je ne vois pas d'exercice sur cette photo. "
                            'Pose ta feuille bien à plat et reprends-la.',
                    actionLabel: widget.photo == null ? 'Modifier' : 'Reprendre la photo',
                    onAction: () => Navigator.of(context).pop(),
                  ),
                _Phase.confirm => _Confirm(
                    quest: _quest!,
                    onYes: _showQuest,
                    onNo: () => Navigator.of(context).pop(),
                  ),
                _Phase.quest => _QuestCard(quest: _quest!),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 80),
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(text, style: const TextStyle(fontSize: 20)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        if (actionLabel != null) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({required this.quest, required this.onYes, required this.onNo});

  final Quest quest;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final question = (quest.questionConfirmation?.isNotEmpty ?? false)
        ? quest.questionConfirmation!
        : "J'ai lu ton exercice. C'est bien ça ?";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Je veux être sûr de bien comprendre',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(quest.enonceTranscrit, style: text.titleMedium),
          ),
        ),
        const SizedBox(height: 16),
        Text(question, style: text.titleMedium),
        const SizedBox(height: 24),
        FilledButton(onPressed: onYes, child: const Text("Oui, c'est ça")),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onNo, child: const Text('Non, je reprends la photo')),
      ],
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quest.titre,
            style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 16),
        Text(quest.scenario, style: text.titleMedium),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.flag_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Ton défi',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(quest.defi, style: text.titleMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_rounded, color: scheme.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(quest.consigneEcriture,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AnswerFlowScreen(quest: quest),
          )),
          child: const Text("J'ai écrit ma réponse : je la montre"),
        ),
      ],
    );
  }
}
