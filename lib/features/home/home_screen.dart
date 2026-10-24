import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/prompt.dart';
import '../../core/quest_theme.dart';
import '../../data/ai_settings.dart';
import '../../demo/demo_widgets.dart';
import '../../game/catalog.dart';
import '../../game/game_state.dart';
import '../../ui/fun_background.dart';
import '../../ui/game_widgets.dart';
import '../../ui/logo.dart';
import '../../ui/mascot.dart';
import '../../ui/pressable.dart';
import '../../ui/universe_art.dart';
import '../../voice/voice_input.dart';
import '../dictee/dictee_screen.dart';
import '../exercices/exercices_screen.dart';
import '../parent/parent_gate.dart';
import '../quest/quest_flow_screen.dart';
import '../scan/photo_capture_view.dart';
import '../shop/shop_screen.dart';
import '../universe/universe_screen.dart';
import '../village/village_screen.dart';

const _ink = Color(0xFF241C3A);

void _open(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(questThemeProvider);
    final game = ref.watch(gameProvider).value ?? const GameState();

    return Scaffold(
      body: FunBackground(
        theme: theme,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 12, wide ? 32 : 16, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(theme: theme, game: game, wide: wide),
                        const SizedBox(height: 18),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _MissionPanel(theme: theme),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text('Choisis ton univers',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        _UniverseRow(selected: theme, wide: wide),
                        const SizedBox(height: 26),
                        _Shortcuts(game: game, wide: wide),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.theme, required this.game, required this.wide});

  final QuestTheme theme;
  final GameState game;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        AppLogo(theme: theme, size: wide ? 40 : 34, showName: wide),
        if (isDemo(ref)) ...[const SizedBox(width: 8), const DemoBadge()],
        const Spacer(),
        LevelBar(xp: game.xp, width: wide ? 110 : 70),
        const SizedBox(width: 10),
        Pressable(
          borderRadius: 40,
          semanticLabel: 'Mes étoiles : ${game.stars}',
          onTap: () => _open(context, const ShopScreen()),
          child: StatPill(
            icon: Icons.star_rounded,
            label: '${game.stars}',
            color: const Color(0xFFF2B84B),
            semanticLabel: '${game.stars} étoiles',
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          borderRadius: 40,
          semanticLabel: 'Mon avatar',
          onTap: () => _open(context, const ShopScreen(initialTab: 0)),
          child: AvatarBadge(game: game, size: wide ? 48 : 42),
        ),
        // Accès parent : discret, protégé par un code PIN.
        Tooltip(
          message: 'Espace parent',
          child: IconButton(
            onPressed: () => _open(context, const ParentGate()),
            icon: Icon(Icons.lock_outline_rounded, color: _ink.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }
}

/// Le scan est ici, sur la première page : une zone de texte extensible, un
/// micro pour dicter, une photo, et un bouton pour lancer la recherche.
class _MissionPanel extends ConsumerStatefulWidget {
  const _MissionPanel({required this.theme});

  final QuestTheme theme;

  @override
  ConsumerState<_MissionPanel> createState() => _MissionPanelState();
}

class _MissionPanelState extends ConsumerState<_MissionPanel> {
  final _text = TextEditingController();
  PickedPhoto? _photo;
  bool _listening = false;
  String? _message;
  String _beforeVoice = '';

  late final VoiceInput _voice;

  /// Vrai dès le début de dispose() : le micro peut répondre à l'arrêt avant
  /// que « mounted » ne passe à faux.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceInputProvider);
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _disposed = true;
    _voice.stop();
    _text.dispose();
    super.dispose();
  }

  bool get _canStart => _photo != null || _text.text.trim().isNotEmpty;

  Future<void> _pick({required bool camera}) async {
    setState(() => _message = null);
    try {
      final photo = await ref.read(photoPickerProvider)(camera: camera);
      if (photo == null || !mounted) return;
      setState(() => _photo = photo);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = "Je n'arrive pas à ouvrir l'appareil photo. "
          'Importe plutôt une photo enregistrée sur cet appareil.');
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _beforeVoice = _text.text.trim();
    setState(() {
      _listening = true;
      _message = null;
    });
    await _voice.start(
      onText: (words, {required isFinal}) {
        if (_disposed || !mounted) return;
        final joined = _beforeVoice.isEmpty ? words : '$_beforeVoice $words';
        _text.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
      },
      onDone: () {
        if (!_disposed && mounted) setState(() => _listening = false);
      },
      onError: (m) {
        if (!_disposed && mounted) setState(() => _message = m);
      },
    );
  }

  void _start() {
    if (_listening) _voice.stop();
    final photo = _photo;
    _open(
      context,
      QuestFlowScreen(
        photo: photo?.bytes,
        mimeType: photo?.mimeType,
        note: cleanNote(_text.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ai = ref.watch(aiSettingsProvider);
    final demo = isDemo(ref);
    final notReady = ai.hasValue && !ai.value!.hasKey && !demo;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: widget.theme.gradient.last.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Mascot(size: 76, scarf: widget.theme.gradient.first),
              const SizedBox(width: 10),
              const Flexible(child: SpeechBubble(text: "C'est l'heure de ta mission du jour !")),
            ],
          ),
          if (demo) ...[
            const SizedBox(height: 10),
            const DemoBanner(),
          ],
          if (notReady) ...[
            const SizedBox(height: 10),
            const _NotReadyBanner(),
            const DemoOfferButton(),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 8,
            maxLength: kNoteMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Écris ou dicte ton exercice : « exercice 3 page 45, les fractions »…',
              filled: true,
              fillColor: const Color(0xFFF6F3FA),
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Tooltip(
                message: _listening ? 'Arrêter la dictée' : 'Dicter à voix haute',
                child: IconButton(
                  onPressed: _toggleVoice,
                  icon: Icon(
                    _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _listening ? const Color(0xFFD32F2F) : scheme.primary,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text("Je t'écoute…",
                  style: text.labelMedium?.copyWith(color: const Color(0xFFD32F2F))),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(_message!,
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _pick(camera: cameraAvailable),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Scanner mon devoir'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
              ),
              if (cameraAvailable)
                OutlinedButton.icon(
                  onPressed: () => _pick(camera: false),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Importer'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                ),
              if (_photo != null)
                _Thumb(photo: _photo!, onRemove: () => setState(() => _photo = null)),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _canStart ? _start : null,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Lancer la recherche'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
        ],
      ),
    );
  }
}

/// Prévient dès l'accueil que la recherche n'est pas configurée, au lieu de
/// laisser découvrir l'erreur après la photo.
class _NotReadyBanner extends StatelessWidget {
  const _NotReadyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFC107), width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_rounded, color: Color(0xFF8A6D00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "La recherche n'est pas encore prête. Demande à un parent de saisir "
              'la clé dans Espace parent, puis Moteur IA.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onRemove});

  final PickedPhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Photo prête',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Image.memory(
                photo.bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.image_rounded),
              ),
            ),
          ),
          Positioned(
            right: -8,
            top: -8,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.cancel_rounded, size: 20, color: Color(0xFFD32F2F)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UniverseRow extends ConsumerWidget {
  const _UniverseRow({required this.selected, required this.wide});

  final QuestTheme selected;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void choose(QuestTheme t) {
      ref.read(questThemeProvider.notifier).select(t);
      _open(context, UniverseScreen(theme: t));
    }

    final cards = [
      for (final t in QuestTheme.values)
        _UniverseCard(theme: t, selected: t == selected, onTap: () => choose(t)),
    ];
    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          cards[i],
        ],
      ],
    );
  }
}

class _UniverseCard extends StatelessWidget {
  const _UniverseCard({required this.theme, required this.selected, required this.onTap});

  final QuestTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      borderRadius: 24,
      shadowColor: theme.gradient.last,
      selected: selected,
      semanticLabel: theme.label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 168,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 4),
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(child: UniverseArt(theme: theme)),
              Positioned(
                left: 16,
                top: 14,
                right: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            theme.label,
                            style: const TextStyle(
                              fontFamily: kHeadingFont,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              color: Colors.white,
                              shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            theme.tagline,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.white,
                              shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(selected ? 'Choisi' : 'Explorer',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: theme.gradient.last,
                              )),
                          Icon(
                            selected ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                            size: 16,
                            color: theme.gradient.last,
                          ),
                        ],
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

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.game, required this.wide});

  final GameState game;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final built = game.buildingLevels.values.fold<int>(0, (a, b) => a + b);
    final total = buildings.length * kBuildingMaxLevel;
    final tiles = [
      _ShortcutTile(
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFF5B6BD6),
        title: 'Mes exercices',
        subtitle: 'Par matière, selon le programme',
        onTap: () => _open(context, const ExercicesScreen()),
      ),
      _ShortcutTile(
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF7C4DDB),
        title: 'Dictée magique',
        subtitle: 'Écoute, écris, corrige',
        onTap: () => _open(context, const DicteeScreen()),
      ),
      _ShortcutTile(
        icon: Icons.holiday_village_rounded,
        color: const Color(0xFF2BA36B),
        title: 'Mon village',
        subtitle: '$built / $total niveaux construits',
        onTap: () => _open(context, const VillageScreen()),
      ),
      _ShortcutTile(
        icon: Icons.storefront_rounded,
        color: const Color(0xFFE0703C),
        title: 'Boutique',
        subtitle: '${game.stars} étoile(s) à dépenser',
        onTap: () => _open(context, const ShopScreen()),
      ),
    ];
    if (wide) {
      return Column(
        children: [
          Row(children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 16),
            Expanded(child: tiles[1]),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: tiles[2]),
            const SizedBox(width: 16),
            Expanded(child: tiles[3]),
          ]),
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          tiles[i],
        ],
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
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
      borderRadius: 20,
      semanticLabel: title,
      onTap: onTap,
      shadowColor: color,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _ink.withValues(alpha: 0.4), size: 28),
          ],
        ),
      ),
    );
  }
}
