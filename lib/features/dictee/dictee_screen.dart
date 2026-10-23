import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/gemini_client.dart';
import '../../core/curriculum.dart';
import '../../core/quest_theme.dart';
import '../../data/progress.dart';
import '../../dictee/dictee_text.dart';
import '../../dictee/speech.dart';
import '../../game/game_state.dart';
import '../../ui/pressable.dart';
import '../../ui/reward_view.dart';
import '../scan/photo_capture_view.dart';

enum _Phase {
  setup,
  typing,
  scanSource,
  preparing,
  confirmText,
  ready,
  dictating,
  capture,
  correcting,
  confirmRead,
  result,
  error,
}

/// Dictée vocale : le texte est lu par la voix de l'appareil et reste caché ;
/// l'enfant écrit sur son cahier, puis photographie sa dictée pour la corriger.
class DicteeScreen extends ConsumerStatefulWidget {
  const DicteeScreen({super.key});

  @override
  ConsumerState<DicteeScreen> createState() => _DicteeScreenState();
}

class _DicteeScreenState extends ConsumerState<DicteeScreen> {
  _Phase _phase = _Phase.setup;

  final _typed = TextEditingController();
  DicteeText? _text;
  List<String> _segments = const [];

  /// -1 : écoute du texte entier ; 0..n-1 : segments ; n : relecture finale.
  int _step = -1;
  int _speakToken = 0;
  bool _speaking = false;
  bool _voiceMissing = false;
  SpeechRate _rate = SpeechRate.normal;
  bool _spokenPunctuation = false;

  DicteeCorrection? _correction;
  final Set<int> _revealed = {};
  Reward? _reward;
  String? _notice;
  String? _errorMessage;
  bool _canRetry = true;
  VoidCallback? _retry;

  /// Lue dès l'ouverture : « ref » ne peut plus être utilisé dans dispose().
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
  }

  @override
  void dispose() {
    _typed.dispose();
    _speech.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- préparation

  void _fail(Object e, VoidCallback retry) {
    final kind = e is GeminiException ? e.kind : null;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = e is GeminiException
          ? e.childMessage
          : "Oups, quelque chose s'est mal passé. Réessaie !";
      _canRetry = kind != GeminiErrorKind.noKey && kind != GeminiErrorKind.auth;
      _retry = retry;
    });
  }

  void _useText(DicteeText t) {
    _text = t;
    _segments = splitDictee(t.texte);
    _step = -1;
    setState(() => _phase = _Phase.ready);
  }

  Future<void> _fromTyped() async {
    final raw = _typed.text.trim();
    final segments = splitDictee(raw);
    if (segments.isEmpty) {
      setState(() => _notice = 'Écris le texte de la dictée avant de continuer.');
      return;
    }
    _notice = null;
    _useText(DicteeText(titre: 'Ma dictée', texte: raw));
  }

  Future<void> _fromPhoto(Uint8List bytes, String mime) async {
    setState(() => _phase = _Phase.preparing);
    try {
      final service = await ref.read(dicteeServiceProvider.future);
      final t = await service.extractText(image: bytes, mimeType: mime);
      if (!mounted) return;
      if (t.lectureIncertaine) {
        _text = t;
        setState(() => _phase = _Phase.confirmText);
      } else {
        _useText(t);
      }
    } catch (e) {
      if (mounted) _fail(e, () => _fromPhoto(bytes, mime));
    }
  }

  Future<void> _generate() async {
    setState(() => _phase = _Phase.preparing);
    try {
      final service = await ref.read(dicteeServiceProvider.future);
      final curriculum = await ref.read(curriculumProvider.future);
      final t = await service.generateText(
        theme: ref.read(questThemeProvider),
        curriculum: curriculum,
      );
      if (!mounted) return;
      _useText(t);
    } catch (e) {
      if (mounted) _fail(e, _generate);
    }
  }

  // ------------------------------------------------------------------- lecture

  String get _fullText => _segments.join(' ');

  String _spokenFor(int step) {
    if (step < 0 || step >= _segments.length) return _fullText;
    final seg = _segments[step];
    return _spokenPunctuation ? withSpokenPunctuation(seg) : seg;
  }

  Future<void> _speak(String text) async {
    final token = ++_speakToken;
    await _speech.stop();
    final ok = await _speech.init();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _voiceMissing = true;
        _speaking = false;
      });
      return;
    }
    setState(() {
      _voiceMissing = false;
      _speaking = true;
    });
    await _speech.speak(text);
    if (mounted && token == _speakToken) setState(() => _speaking = false);
  }

  Future<void> _goTo(int step) async {
    setState(() {
      _step = step.clamp(-1, _segments.length);
      _phase = _Phase.dictating;
    });
    await _speak(_spokenFor(_step));
  }

  Future<void> _setRate(SpeechRate r) async {
    setState(() => _rate = r);
    await _speech.setRate(r);
    if (_phase == _Phase.dictating) await _speak(_spokenFor(_step));
  }

  Future<void> _start() async {
    await _speech.setRate(_rate);
    await _goTo(-1);
  }

  // ---------------------------------------------------------------- correction

  Future<void> _correct(Uint8List bytes, String mime) async {
    setState(() {
      _phase = _Phase.correcting;
      _notice = null;
    });
    try {
      final service = await ref.read(dicteeServiceProvider.future);
      final curriculum = await ref.read(curriculumProvider.future);
      final c = await service.correct(
        image: bytes,
        mimeType: mime,
        texteSource: _text!.texte,
        curriculum: curriculum,
      );
      if (!mounted) return;
      if (!c.estUneDictee) {
        setState(() {
          _phase = _Phase.capture;
          _notice = "Je ne vois pas de dictée écrite sur cette photo. "
              'Pose ton cahier bien à plat et reprends la photo.';
        });
        return;
      }
      if (c.lectureIncertaine) {
        _correction = c;
        setState(() => _phase = _Phase.confirmRead);
        return;
      }
      await _finish(c);
    } catch (e) {
      if (mounted) _fail(e, () => _correct(bytes, mime));
    }
  }

  Future<void> _finish(DicteeCorrection c) async {
    final now = DateTime.now();
    final progress = ref.read(progressProvider.notifier);
    for (final comp in c.competences) {
      await progress.recordAttempt(Attempt(
        competenceId: comp.id,
        date: now,
        success: comp.reussie,
      ));
    }
    await progress.addScan(ScanRecord(
      id: now.microsecondsSinceEpoch.toString(),
      date: now,
      themeLabel: ref.read(questThemeProvider).label,
      matiereId: 'francais',
      note: _text?.titre,
      kind: kindDictee,
      errors: {for (final e in c.parCategorie.entries) e.key.name: e.value},
    ));
    final reward = await ref
        .read(gameProvider.notifier)
        .applyReward(computeDicteeReward(errors: c.nbErreurs));
    if (!mounted) return;
    setState(() {
      _correction = c;
      _reward = reward;
      _revealed.clear();
      _phase = _Phase.result;
    });
  }

  // ------------------------------------------------------------------- écran

  @override
  Widget build(BuildContext context) {
    final body = switch (_phase) {
      _Phase.setup => _Setup(
          notice: _notice,
          onScan: () => setState(() => _phase = _Phase.scanSource),
          onType: () => setState(() => _phase = _Phase.typing),
          onGenerate: _generate,
        ),
      _Phase.typing => _Typing(
          controller: _typed,
          notice: _notice,
          onContinue: _fromTyped,
        ),
      _Phase.scanSource => PhotoCaptureView(
          header: const _Banner(
            text: 'Photographie le texte de la dictée. Un adulte s\'en charge : '
                "l'enfant ne doit pas le lire.",
          ),
          emptyHint: 'Pose la feuille du texte à dicter bien à plat.',
          confirmLabel: 'Lire ce texte',
          onConfirm: _fromPhoto,
        ),
      _Phase.preparing => const _Wait(text: 'Je prépare ta dictée…'),
      _Phase.confirmText => _ConfirmText(
          text: _text!,
          onYes: () => _useText(_text!),
          onNo: () => setState(() => _phase = _Phase.scanSource),
        ),
      _Phase.ready => _Ready(
          segments: _segments.length,
          titre: _text!.titre,
          rate: _rate,
          spokenPunctuation: _spokenPunctuation,
          onRate: _setRate,
          onPunctuation: (v) => setState(() => _spokenPunctuation = v),
          onStart: _start,
        ),
      _Phase.dictating => _Dictating(
          step: _step,
          total: _segments.length,
          speaking: _speaking,
          voiceMissing: _voiceMissing,
          rate: _rate,
          onRate: _setRate,
          onRepeat: () => _speak(_spokenFor(_step)),
          onPrevious: _step > -1 ? () => _goTo(_step - 1) : null,
          onNext: () {
            if (_step >= _segments.length) {
              _speech.stop();
              setState(() => _phase = _Phase.capture);
            } else {
              _goTo(_step + 1);
            }
          },
        ),
      _Phase.capture => PhotoCaptureView(
          key: const ValueKey('capture-dictee'),
          header: _notice == null ? null : _Banner(text: _notice!),
          emptyHint: 'Prends en photo ta dictée écrite sur ton cahier.',
          confirmLabel: 'Corriger ma dictée',
          onConfirm: _correct,
        ),
      _Phase.correcting => const _Wait(text: 'Je corrige ta dictée…'),
      _Phase.confirmRead => _ConfirmRead(
          correction: _correction!,
          onYes: () => _finish(_correction!),
          onNo: () => setState(() {
            _phase = _Phase.capture;
            _notice = 'Reprends la photo en écrivant bien lisiblement.';
          }),
        ),
      _Phase.result => _Result(
          correction: _correction!,
          revealed: _revealed,
          reward: _reward,
          onReveal: (i) => setState(() => _revealed.add(i)),
          onDone: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      _Phase.error => _Centered(
          child: Column(
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(_errorMessage ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              if (_canRetry && _retry != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: _retry, child: const Text('Réessayer')),
              ],
            ],
          ),
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictée magique'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(child: body),
    );
  }
}

// ----------------------------------------------------------------- composants

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      );
}

class _Wait extends StatelessWidget {
  const _Wait({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _Centered(
        child: Column(
          children: [
            const SizedBox(height: 60),
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(text, style: const TextStyle(fontSize: 20)),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
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
      shadowColor: color,
      semanticLabel: title,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: Colors.white, size: 36),
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
          ],
        ),
      ),
    );
  }
}

class _Setup extends StatelessWidget {
  const _Setup({
    required this.onScan,
    required this.onType,
    required this.onGenerate,
    this.notice,
  });

  final VoidCallback onScan;
  final VoidCallback onType;
  final VoidCallback onGenerate;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Où est le texte de la dictée ?',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Le texte reste caché : je le lis à voix haute, et tu écris sur ton cahier.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _OptionCard(
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFF7C5CFF),
            title: 'Dictée surprise',
            subtitle: 'Je t\'invente une dictée dans ton univers.',
            onTap: onGenerate,
          ),
          const SizedBox(height: 14),
          _OptionCard(
            icon: Icons.photo_camera_rounded,
            color: const Color(0xFFFF8A3D),
            title: 'Photographier le texte',
            subtitle: 'Un adulte prend en photo la dictée de la classe.',
            onTap: onScan,
          ),
          const SizedBox(height: 14),
          _OptionCard(
            icon: Icons.keyboard_rounded,
            color: const Color(0xFF2FAE66),
            title: 'Écrire le texte',
            subtitle: 'Un adulte tape ou colle le texte à dicter.',
            onTap: onType,
          ),
        ],
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing({required this.controller, required this.onContinue, this.notice});

  final TextEditingController controller;
  final VoidCallback onContinue;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Banner(text: "Ce texte est réservé à l'adulte : l'enfant ne doit pas le lire."),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Texte de la dictée',
              alignLabelWithHint: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(notice!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: onContinue, child: const Text('Préparer la dictée')),
        ],
      ),
    );
  }
}

class _ConfirmText extends StatelessWidget {
  const _ConfirmText({required this.text, required this.onYes, required this.onNo});

  final DicteeText text;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final q = (text.questionConfirmation?.isNotEmpty ?? false)
        ? text.questionConfirmation!
        : "Le texte est-il bien celui de la dictée ?";
    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Banner(
            text: "Un adulte doit vérifier ce texte. L'enfant ne doit pas regarder l'écran.",
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(text.texte, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          const SizedBox(height: 12),
          Text(q, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton(onPressed: onYes, child: const Text("Oui, c'est le bon texte")),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onNo, child: const Text('Non, reprendre la photo')),
        ],
      ),
    );
  }
}

class _RateChips extends StatelessWidget {
  const _RateChips({required this.rate, required this.onRate});

  final SpeechRate rate;
  final ValueChanged<SpeechRate> onRate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.speed_rounded),
        for (final r in SpeechRate.values)
          ChoiceChip(
            label: Text(r.label),
            selected: rate == r,
            onSelected: (_) => onRate(r),
          ),
      ],
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.segments,
    required this.titre,
    required this.rate,
    required this.spokenPunctuation,
    required this.onRate,
    required this.onPunctuation,
    required this.onStart,
  });

  final int segments;
  final String titre;
  final SpeechRate rate;
  final bool spokenPunctuation;
  final ValueChanged<SpeechRate> onRate;
  final ValueChanged<bool> onPunctuation;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.record_voice_over_rounded,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('Ta dictée est prête !',
              textAlign: TextAlign.center, style: text.headlineMedium),
          const SizedBox(height: 6),
          Text('$titre · $segments morceau(x) à écrire',
              textAlign: TextAlign.center, style: text.titleSmall),
          const SizedBox(height: 20),
          const _Banner(text: 'Prépare ton cahier et ton stylo. Le texte reste caché.'),
          const SizedBox(height: 16),
          Text('Vitesse de la voix', style: text.titleMedium),
          const SizedBox(height: 8),
          _RateChips(rate: rate, onRate: onRate),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: spokenPunctuation,
            onChanged: onPunctuation,
            title: const Text('Dire la ponctuation'),
            subtitle: const Text('« virgule », « point »… comme à l\'école'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Commencer la dictée'),
          ),
        ],
      ),
    );
  }
}

class _Dictating extends StatelessWidget {
  const _Dictating({
    required this.step,
    required this.total,
    required this.speaking,
    required this.voiceMissing,
    required this.rate,
    required this.onRate,
    required this.onRepeat,
    required this.onNext,
    this.onPrevious,
  });

  final int step;
  final int total;
  final bool speaking;
  final bool voiceMissing;
  final SpeechRate rate;
  final ValueChanged<SpeechRate> onRate;
  final VoidCallback onRepeat;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isIntro = step < 0;
    final isFinal = step >= total;

    final title = isIntro
        ? 'Écoute tout le texte'
        : isFinal
            ? 'Relis-toi avec moi'
            : 'Morceau ${step + 1} sur $total';
    final hint = isIntro
        ? "Écoute d'abord sans écrire."
        : isFinal
            ? 'Je lis tout une dernière fois : relis ta dictée et corrige-toi.'
            : 'Écris ce que tu entends sur ton cahier.';
    final nextLabel = isIntro
        ? "J'ai écouté : on commence"
        : isFinal
            ? "J'ai fini : je montre ma dictée"
            : "J'ai écrit : morceau suivant";

    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isIntro && !isFinal)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (step + 1) / total,
                minHeight: 12,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 20),
          Pressable(
            borderRadius: 40,
            semanticLabel: 'Répéter',
            onTap: onRepeat,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Column(
                children: [
                  Icon(
                    speaking ? Icons.volume_up_rounded : Icons.volume_mute_rounded,
                    size: 84,
                    color: speaking ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(
                    speaking ? 'Je lis…' : 'Touche pour réécouter',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 14),
                  // Le texte reste masqué : seuls des points indiquent qu'il existe.
                  Text('• • • • • • • •',
                      style: TextStyle(fontSize: 22, letterSpacing: 4, color: scheme.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(hint, textAlign: TextAlign.center, style: text.titleMedium),
          if (voiceMissing) ...[
            const SizedBox(height: 12),
            _Banner(
              text: "Cet appareil n'a pas de voix française. Un adulte peut lire le "
                  "texte à voix haute à la place, ou tu peux essayer sur un autre appareil.",
            ),
          ],
          const SizedBox(height: 16),
          Center(child: _RateChips(rate: rate, onRate: onRate)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous_rounded),
                  label: const Text('Avant'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRepeat,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Répéter'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onNext, child: Text(nextLabel, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _ConfirmRead extends StatelessWidget {
  const _ConfirmRead({required this.correction, required this.onYes, required this.onNo});

  final DicteeCorrection correction;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = (correction.questionConfirmation?.isNotEmpty ?? false)
        ? correction.questionConfirmation!
        : "J'ai du mal à lire certains mots. J'ai bien lu ta dictée ?";
    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Je veux être sûr de bien lire',
              style: text.headlineSmall),
          const SizedBox(height: 16),
          if (correction.texteLu.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(correction.texteLu, style: text.titleMedium),
              ),
            ),
          const SizedBox(height: 12),
          Text(q, style: text.titleMedium),
          const SizedBox(height: 20),
          FilledButton(onPressed: onYes, child: const Text("Oui, c'est ça")),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onNo, child: const Text('Non, je reprends la photo')),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.correction,
    required this.revealed,
    required this.onReveal,
    required this.onDone,
    this.reward,
  });

  final DicteeCorrection correction;
  final Set<int> revealed;
  final ValueChanged<int> onReveal;
  final VoidCallback onDone;
  final Reward? reward;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = correction.nbErreurs;
    final title = n == 0
        ? 'Dictée sans faute, bravo !'
        : n == 1
            ? 'Plus qu\'une erreur à corriger'
            : '$n erreurs à corriger';
    return _Centered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            n == 0 ? Icons.emoji_events_rounded : Icons.edit_note_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: text.headlineMedium),
          if (correction.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(correction.message, textAlign: TextAlign.center, style: text.titleMedium),
          ],
          if (n > 0) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in correction.parCategorie.entries)
                  Chip(
                    avatar: CircleAvatar(
                      backgroundColor: e.key.color,
                      child: Text('${e.value}',
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    label: Text(e.key.label),
                    side: BorderSide(color: e.key.color, width: 2),
                    backgroundColor: Colors.white,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Essaie de trouver la bonne écriture avant de toucher « Voir la correction ».',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < correction.erreurs.length; i++)
              _ErrorCard(
                error: correction.erreurs[i],
                revealed: revealed.contains(i),
                onReveal: () => onReveal(i),
              ),
          ],
          if (reward != null) ...[
            const SizedBox(height: 16),
            RewardView(reward: reward!),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: onDone, child: const Text('Terminer')),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.revealed, required this.onReveal});

  final DicteeError error;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: error.categorie.color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(error.categorie.label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error.motEcrit.isEmpty ? 'Mot oublié' : 'Tu as écrit « ${error.motEcrit} »',
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
            if (error.explication.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error.explication, style: text.bodyMedium),
            ],
            const SizedBox(height: 8),
            revealed
                ? Text('On attendait « ${error.motAttendu} »',
                    style: text.titleMedium?.copyWith(color: const Color(0xFF2E7D32)))
                : TextButton(onPressed: onReveal, child: const Text('Voir la correction')),
          ],
        ),
      ),
    );
  }
}
