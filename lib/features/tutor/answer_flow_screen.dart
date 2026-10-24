import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/gemini_client.dart';
import '../../ai/quest.dart';
import '../../ai/tutor.dart';
import '../../core/curriculum.dart';
import '../../core/quest_theme.dart';
import '../../data/progress.dart';
import '../../game/game_state.dart';
import '../../demo/demo_widgets.dart';
import '../../ui/reward_view.dart';
import '../scan/photo_capture_view.dart';

/// Durée minimale de lecture de la capsule avant de pouvoir passer au quiz.
const Duration kLectureCapsule = Duration(seconds: 20);

/// Durée minimale quand l'élève relit la capsule après une erreur au quiz.
const Duration kRelectureCapsule = Duration(seconds: 10);

enum _Phase {
  capture,
  verifying,
  confirmRead,
  correct,
  hint,
  capsuleLoading,
  capsule,
  quiz,
  error,
}

/// Réponse manuscrite → vérification → indices socratiques → capsule
/// « Bon à savoir » (lecture contrôlée) → même défi, jusqu'à la réussite.
class AnswerFlowScreen extends ConsumerStatefulWidget {
  const AnswerFlowScreen({
    super.key,
    required this.quest,
    this.minRead = kLectureCapsule,
    this.minReread = kRelectureCapsule,
  });

  final Quest quest;
  final Duration minRead;
  final Duration minReread;

  @override
  ConsumerState<AnswerFlowScreen> createState() => _AnswerFlowScreenState();
}

class _AnswerFlowScreenState extends ConsumerState<AnswerFlowScreen> {
  _Phase _phase = _Phase.capture;

  int _fails = 0;
  int _capsulesDone = 0;
  int _totalAttempts = 0;
  String? _notice;
  String? _hint;
  String? _errorMessage;
  bool _canRetryError = true;

  Verification? _pending;
  Reward? _reward;
  Uint8List? _lastPhoto;
  String _lastMime = 'image/jpeg';

  Capsule? _capsule;
  int _quizIndex = 0;
  String? _quizFeedback;
  int? _wrongChoice;

  Timer? _timer;
  Duration _remaining = Duration.zero;

  Competence? _competence;

  @override
  void initState() {
    super.initState();
    _loadCompetence();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCompetence() async {
    final id = widget.quest.competenceId;
    if (id == null) return;
    final c = await ref.read(curriculumProvider.future);
    _competence = c.competence(id);
  }

  void _startTimer(Duration d) {
    _timer?.cancel();
    setState(() => _remaining = d);
    if (d <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          t.cancel();
        }
      });
    });
  }

  void _fail(Object e) {
    final kind = e is GeminiException ? e.kind : null;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = e is GeminiException
          ? e.childMessage
          : "Oups, quelque chose s'est mal passé. Réessaie !";
      _canRetryError =
          kind != GeminiErrorKind.noKey && kind != GeminiErrorKind.auth;
    });
  }

  Future<void> _verify(Uint8List bytes, String mime) async {
    _lastPhoto = bytes;
    _lastMime = mime;
    setState(() {
      _phase = _Phase.verifying;
      _notice = null;
    });
    try {
      await _loadCompetence();
      final tutor = await ref.read(tutorServiceProvider.future);
      final v = await tutor.verifyAnswer(
        image: bytes,
        mimeType: mime,
        quest: widget.quest,
        competence: _competence,
        theme: ref.read(questThemeProvider),
        attemptNumber: _fails + 1,
      );
      if (!mounted) return;
      if (!v.estUneReponse) {
        setState(() {
          _phase = _Phase.capture;
          _notice = "Je ne vois pas de réponse écrite sur cette photo. "
              'Écris ta réponse sur ton cahier, puis reprends la photo.';
        });
        return;
      }
      if (v.lectureIncertaine) {
        setState(() {
          _pending = v;
          _phase = _Phase.confirmRead;
        });
        return;
      }
      await _applyVerdict(v);
    } catch (e) {
      if (mounted) _fail(e);
    }
  }

  Future<void> _applyVerdict(Verification v) async {
    _totalAttempts++;
    final competenceId = widget.quest.competenceId;
    var becameAcquired = false;
    var cappedToday = false;
    if (competenceId != null) {
      final progress = ref.read(progressProvider.notifier);
      final before = await ref.read(progressProvider.future);
      final statusBefore = before.statusOf(competenceId);
      final now = DateTime.now();
      final winsToday = before
          .attemptsFor(competenceId)
          .where((a) =>
              a.success &&
              a.date.year == now.year &&
              a.date.month == now.month &&
              a.date.day == now.day)
          .length;
      cappedToday = v.correct && winsToday >= kReussitesRecompenseesParJour;
      await progress.recordAttempt(Attempt(
        competenceId: competenceId,
        date: now,
        success: v.correct,
        capsuleRead: _capsulesDone > 0,
      ));
      final after = await ref.read(progressProvider.future);
      becameAcquired = statusBefore != CompetenceStatus.acquise &&
          after.statusOf(competenceId) == CompetenceStatus.acquise;
    }
    if (!mounted) return;
    if (v.correct) {
      final reward = await ref.read(gameProvider.notifier).applyReward(
            computeReward(
              matiereId: widget.quest.matiereId,
              fails: _fails,
              capsules: _capsulesDone,
              becameAcquired: becameAcquired,
              cappedToday: cappedToday,
            ),
          );
      if (!mounted) return;
      setState(() {
        _hint = v.message;
        _reward = reward;
        _phase = _Phase.correct;
      });
      return;
    }
    _fails++;
    if (_fails >= kEssaisAvantCapsule) {
      await _openCapsule();
      return;
    }
    setState(() {
      _hint = safeHint(v.message, v.reponseAttendue);
      _phase = _Phase.hint;
    });
  }

  Future<void> _openCapsule() async {
    if (_capsule != null) {
      _quizIndex = 0;
      _startTimer(widget.minRead);
      setState(() => _phase = _Phase.capsule);
      return;
    }
    setState(() => _phase = _Phase.capsuleLoading);
    try {
      final tutor = await ref.read(tutorServiceProvider.future);
      final capsule = await tutor.createCapsule(
        quest: widget.quest,
        competence: _competence,
        theme: ref.read(questThemeProvider),
      );
      if (!mounted) return;
      _capsule = capsule;
      _quizIndex = 0;
      _startTimer(widget.minRead);
      setState(() => _phase = _Phase.capsule);
    } catch (e) {
      if (mounted) _fail(e);
    }
  }

  void _toQuiz() {
    _timer?.cancel();
    setState(() {
      _quizIndex = 0;
      _quizFeedback = null;
      _wrongChoice = null;
      _phase = _Phase.quiz;
    });
  }

  void _answerQuiz(int choice) {
    final q = _capsule!.quiz[_quizIndex];
    if (choice == q.bonneReponse) {
      if (_quizIndex + 1 >= _capsule!.quiz.length) {
        // Capsule comprise : on repart sur le même défi avec trois nouveaux essais.
        ref.read(gameProvider.notifier).addXp(kXpCapsuleComprise);
        setState(() {
          _capsulesDone++;
          _fails = 0;
          _quizFeedback = null;
          _wrongChoice = null;
          _notice = 'Bravo, tu as bien lu la capsule ! +$kXpCapsuleComprise XP. '
              'Retente maintenant le même défi.';
          _phase = _Phase.capture;
        });
      } else {
        setState(() {
          _quizIndex++;
          _quizFeedback = null;
          _wrongChoice = null;
        });
      }
    } else {
      setState(() => _wrongChoice = choice);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _startTimer(widget.minReread);
        setState(() {
          _quizFeedback = "Pas tout à fait. Relis bien la capsule, puis réessaie le quiz.";
          _wrongChoice = null;
          _phase = _Phase.capsule;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_phase) {
      _Phase.capture => PhotoCaptureView(
          key: ValueKey('capture-$_totalAttempts-$_capsulesDone'),
          header: _DefiHeader(quest: widget.quest, notice: _notice),
          emptyHint: 'Prends en photo ta réponse écrite sur ton cahier.',
          confirmLabel: 'Vérifier ma réponse',
          onConfirm: _verify,
        ),
      _Phase.verifying => const _Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('Je regarde ta réponse…', style: TextStyle(fontSize: 20)),
            ],
          ),
        ),
      _Phase.confirmRead => _Center(child: _ConfirmRead(
          verification: _pending!,
          onYes: () => _applyVerdict(_pending!),
          onNo: () => setState(() {
            _phase = _Phase.capture;
            _notice = 'Reprends la photo en écrivant bien lisiblement.';
          }),
        )),
      _Phase.correct => _Center(child: _Correct(
          message: _hint ?? 'Bravo !',
          attempts: _totalAttempts,
          reward: _reward,
          onDone: () => Navigator.of(context).popUntil((r) => r.isFirst),
        )),
      _Phase.hint => _Center(child: _Hint(
          hint: _hint ?? '',
          remaining: kEssaisAvantCapsule - _fails,
          onRetry: () => setState(() => _phase = _Phase.capture),
        )),
      _Phase.capsuleLoading => const _Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('Je prépare un petit rappel pour toi…',
                  style: TextStyle(fontSize: 20)),
            ],
          ),
        ),
      _Phase.capsule => _Center(child: _CapsuleView(
          capsule: _capsule!,
          remaining: _remaining,
          feedback: _quizFeedback,
          askAdult: _capsulesDone >= 1,
          onRead: _toQuiz,
        )),
      _Phase.quiz => _Center(child: _QuizView(
          capsule: _capsule!,
          index: _quizIndex,
          wrongChoice: _wrongChoice,
          onChoose: _answerQuiz,
        )),
      _Phase.error => _Center(child: _ErrorView(
          message: _errorMessage ?? '',
          onRetry: _canRetryError
              ? () {
                  if (_fails >= kEssaisAvantCapsule) {
                    _openCapsule();
                  } else if (_lastPhoto != null) {
                    _verify(_lastPhoto!, _lastMime);
                  } else {
                    setState(() => _phase = _Phase.capture);
                  }
                }
              : null,
        )),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma réponse'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(child: body),
    );
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}

class _DefiHeader extends StatelessWidget {
  const _DefiHeader({required this.quest, this.notice});

  final Quest quest;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DemoVerdictChooser(),
        if (notice != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(notice!, style: text.titleSmall),
          ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ton défi',
                    style: text.labelLarge?.copyWith(color: scheme.primary)),
                const SizedBox(height: 4),
                Text(quest.defi),
                const SizedBox(height: 8),
                Text(quest.consigneEcriture,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfirmRead extends StatelessWidget {
  const _ConfirmRead({
    required this.verification,
    required this.onYes,
    required this.onNo,
  });

  final Verification verification;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = (verification.questionConfirmation?.isNotEmpty ?? false)
        ? verification.questionConfirmation!
        : "J'ai lu « ${verification.reponseLue} ». C'est bien ça ?";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Je veux être sûr de bien lire',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(q, style: text.titleMedium),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onYes, child: const Text("Oui, c'est ça")),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onNo, child: const Text('Non, je reprends la photo')),
      ],
    );
  }
}

class _Correct extends StatelessWidget {
  const _Correct({
    required this.message,
    required this.attempts,
    required this.onDone,
    this.reward,
  });

  final String message;
  final int attempts;
  final VoidCallback onDone;
  final Reward? reward;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.emoji_events_rounded, size: 96, color: scheme.primary),
        const SizedBox(height: 16),
        Text('Défi réussi !',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(message, style: text.titleMedium, textAlign: TextAlign.center),
        if (reward != null) ...[
          const SizedBox(height: 20),
          RewardView(reward: reward!),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: const Text('Terminer')),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.hint, required this.remaining, required this.onRetry});

  final String hint;
  final int remaining;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lightbulb_rounded, size: 64, color: scheme.primary),
        const SizedBox(height: 12),
        Text("Pas encore, mais tu y es presque !",
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(hint, style: text.titleMedium),
          ),
        ),
        const SizedBox(height: 8),
        Text('Il te reste $remaining essai(s) avant le petit rappel de leçon.',
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: onRetry, child: const Text('Je réessaie')),
      ],
    );
  }
}

class _CapsuleView extends StatelessWidget {
  const _CapsuleView({
    required this.capsule,
    required this.remaining,
    required this.onRead,
    required this.askAdult,
    this.feedback,
  });

  final Capsule capsule;
  final Duration remaining;
  final VoidCallback onRead;
  final bool askAdult;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final waiting = remaining > Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, color: scheme.primary, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Bon à savoir : ${capsule.titre}',
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        if (feedback != null) ...[
          const SizedBox(height: 12),
          Text(feedback!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(capsule.lecon, style: text.titleMedium),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'À retenir (recopie-le sur ton cahier) : ${capsule.aRetenir}',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (askAdult) ...[
          const SizedBox(height: 12),
          const Text("Si c'est encore difficile, demande de l'aide à un adulte.",
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: waiting ? null : onRead,
          child: Text(waiting
              ? "Prends le temps de lire… ${remaining.inSeconds + 1} s"
              : "J'ai lu : passer aux 2 questions"),
        ),
      ],
    );
  }
}

class _QuizView extends StatelessWidget {
  const _QuizView({
    required this.capsule,
    required this.index,
    required this.onChoose,
    this.wrongChoice,
  });

  final Capsule capsule;
  final int index;
  final int? wrongChoice;
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = capsule.quiz[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Question ${index + 1} sur ${capsule.quiz.length}',
            style: text.labelLarge),
        const SizedBox(height: 8),
        Text(q.question,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        for (var i = 0; i < q.choix.length; i++) ...[
          FilledButton.tonal(
            style: wrongChoice == i
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.errorContainer)
                : null,
            onPressed: wrongChoice == null ? () => onChoose(i) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(q.choix[i], textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.cloud_off_rounded,
            size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        if (onRetry != null) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ],
    );
  }
}
