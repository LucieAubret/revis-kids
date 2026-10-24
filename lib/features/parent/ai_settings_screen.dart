import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/api_key.dart';
import '../../ai/gemini_client.dart';
import '../../data/ai_settings.dart';

/// Réglages du moteur IA, réservés au parent : clé API Gemini et modèle.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  bool _show = false;
  String? _status;
  bool _statusOk = false;
  GeminiErrorKind? _lastKind;

  /// Modèles réellement utilisables avec la clé, une fois la clé reconnue.
  List<String> _models = const [];

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(aiSettingsProvider.notifier);
    final current = ref.read(aiSettingsProvider).value;
    final typed = _keyCtrl.text.trim();
    final saved = typed.isEmpty ? current?.apiKey : sanitizeApiKey(typed);
    await notifier.save(apiKey: saved, model: _modelCtrl.text);
    _keyCtrl.clear();
    if (!mounted) return;
    setState(() {
      _status = 'Réglages enregistrés.';
      _statusOk = true;
      _lastKind = null;
    });
  }

  /// Texte clair pour chaque cause possible, avec le motif donné par Google.
  String _explain(GeminiException e, String model) {
    final d = e.detail;
    final more = (d == null || d.isEmpty) ? '' : ' (Google : $d)';
    return switch (e.kind) {
      GeminiErrorKind.invalidKey =>
        'La clé contient des caractères non valides (espace, retour à la ligne, '
            'guillemets…). Copiez-la à nouveau, sans rien autour.',
      GeminiErrorKind.keyRejected =>
        "Google ne reconnaît pas cette clé (erreur ACCESS_TOKEN_TYPE_UNSUPPORTED). "
            'Les clés commençant par « AQ. » sont le nouveau format normal de Google AI Studio, '
            'mais celle-ci est refusée : elle est peut-être incomplète (copie coupée), supprimée, '
            "ou créée pour un autre produit (Vertex AI). Recréez-en une dans AI Studio et "
            'copiez-la en entier. Le diagnostic ci-dessous montre la réponse exacte de Google.',      GeminiErrorKind.auth =>
        'Clé refusée par Google. Vérifiez-la, ou créez-en une nouvelle dans Google AI Studio.',
      GeminiErrorKind.serviceBlocked =>
        "La clé est reconnue, mais l'API Gemini est désactivée ou bloquée pour son projet$more. "
            'Dans Google AI Studio, créez la clé pour « Gemini API », ou activez '
            '« Generative Language API » dans le projet.',
      GeminiErrorKind.permissionDenied =>
        'La clé est reconnue, mais elle n\'a pas le droit d\'utiliser « $model »$more.',
      GeminiErrorKind.quota =>
        'Quota atteint pour « $model »$more. Essayez un autre modèle ou activez la '
            'facturation dans Google AI Studio.',
      GeminiErrorKind.modelNotFound =>
        'Le modèle « ${d ?? model} » est introuvable avec cette clé.',
      GeminiErrorKind.network =>
        'La requête vers Google a échoué${d == null ? '' : ' ($d)'}. Causes possibles : '
            'réseau coupé, bloqueur de publicités ou antivirus, ou clé refusée par Google '
            "(Safari affiche alors « Load failed » sans montrer la raison). "
            'Le diagnostic ci-dessous montre la réponse exacte de Google.',
      GeminiErrorKind.unknown =>
        'Erreur inattendue${d == null ? '' : ' ($d)'}. Signalez-la telle quelle.',
      _ => 'Le test a échoué (${e.kind.name}${d == null ? '' : ', $d'}).',
    };
  }

  Future<void> _test() async {
    final current = ref.read(aiSettingsProvider).value;
    final typed = sanitizeApiKey(_keyCtrl.text);
    final key = typed.isEmpty ? current?.apiKey : typed;
    if (key == null || key.isEmpty) {
      setState(() {
        _status = "Saisissez d'abord une clé.";
        _statusOk = false;
        _models = const [];
      });
      return;
    }
    final model = _modelCtrl.text.trim().isEmpty ? kDefaultGeminiModel : _modelCtrl.text.trim();
    final client = ref.read(geminiClientFactoryProvider)(key, model);
    setState(() {
      _busy = true;
      _status = null;
      _models = const [];
    });

    // Étape 1 : la clé elle-même, indépendamment du modèle.
    List<String> available;
    try {
      available = await client.listModels();
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _explain(e, model);
        _statusOk = false;
        _lastKind = e.kind;
        _busy = false;
      });
      return;
    }

    // Étape 2 : le modèle choisi répond-il vraiment ?
    try {
      await client.testConnection();
      if (!mounted) return;
      setState(() {
        _status = 'Connexion réussie : la clé et « $model » fonctionnent. '
            'Touchez « Enregistrer » pour les conserver.';
        _statusOk = true;
        _lastKind = null;
        _models = available.where((m) => m != model).toList();
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'La clé est valide, mais « $model » ne répond pas. ${_explain(e, model)}'
            '${available.isEmpty ? '' : ' Essayez un autre modèle :'}';
        _statusOk = false;
        _lastKind = e.kind;
        _models = available.where((m) => m != model).toList();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Les erreurs dont la cause exacte n'est pas lisible dans le navigateur.
  bool _showsDiagnostic(GeminiErrorKind k) => const {
        GeminiErrorKind.network,
        GeminiErrorKind.keyRejected,
        GeminiErrorKind.auth,
        GeminiErrorKind.unknown,
      }.contains(k);

  void _pick(String model) {
    _modelCtrl.text = model;
    _test();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final text = Theme.of(context).textTheme;

    settings.whenData((s) {
      if (!_loaded) {
        _loaded = true;
        _modelCtrl.text = s.model;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moteur IA'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Clé API Gemini',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(settings.value?.hasKey == true
                    ? 'Clé enregistrée : ${settings.value!.maskedKey}'
                    : 'Aucune clé enregistrée.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: settings.value?.hasKey == true
                        ? 'Nouvelle clé (laisser vide pour conserver)'
                        : 'Clé API',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _show ? 'Masquer' : 'Afficher',
                      icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modelCtrl,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Modèle',
                    helperText: 'Par défaut : $kDefaultGeminiModel',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(onPressed: _busy ? null : _save, child: const Text('Enregistrer')),
                    OutlinedButton(
                      onPressed: _busy ? null : _test,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Tester la connexion'),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: _statusOk
                          ? const Color(0xFF2E7D32)
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (!_statusOk && _lastKind != null && _showsDiagnostic(_lastKind!)) ...[
                  const SizedBox(height: 12),
                  _DiagnosticCard(model: _modelCtrl.text.trim().isEmpty
                      ? kDefaultGeminiModel
                      : _modelCtrl.text.trim()),
                ],
                if (_models.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Modèles disponibles avec votre clé :', style: text.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _models)
                        ActionChip(
                          label: Text(m),
                          onPressed: _busy ? null : () => _pick(m),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Confidentialité. Pour analyser un devoir, la photo est '
                      'envoyée à Google (Gemini) afin d\'être analysée. '
                      "L'application ne la conserve pas. Selon les conditions de Google, "
                      "l'offre gratuite de l'API peut réutiliser les données pour "
                      "améliorer ses produits : pour des devoirs d'enfant, privilégiez "
                      'une offre avec facturation activée. '
                      "La clé est enregistrée sur cet appareil uniquement ; ne l'utilisez "
                      "pas sur un appareil partagé.",
                      style: text.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aide au diagnostic : depuis le Terminal du Mac, la réponse de Google est
/// affichée en entier, alors que Safari la masque (« Load failed »). La clé est
/// lue dans le presse-papiers : elle n'est jamais tapée ni affichée.
class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.model});

  final String model;

  String get command =>
      'curl -s -i "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent" '
      '-H "Content-Type: application/json" -H "x-goog-api-key: \$(pbpaste)" '
      '-d \'{"contents":[{"parts":[{"text":"Dis ok"}]}]}\' | head -40';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diagnostic dans le Terminal',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              '1. Copiez votre clé (⌘C).\n'
              '2. Ouvrez l\'application Terminal du Mac.\n'
              '3. Touchez « Copier la commande », collez-la dans le Terminal (⌘V) puis Entrée.\n'
              'Google répond en toutes lettres. Une ligne « HTTP/2 200 » veut dire que la clé '
              'fonctionne. La clé n\'apparaît pas dans le résultat.',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                command,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copier la commande'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: command));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Commande copiée.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
