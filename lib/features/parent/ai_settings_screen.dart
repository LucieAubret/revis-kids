import 'package:flutter/material.dart';
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
    await notifier.save(
      apiKey: typed.isEmpty ? current?.apiKey : typed,
      model: _modelCtrl.text,
    );
    _keyCtrl.clear();
    if (!mounted) return;
    setState(() {
      _status = 'Réglages enregistrés.';
      _statusOk = true;
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
      GeminiErrorKind.auth =>
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
        'Google est injoignable depuis cet appareil${d == null ? '' : ' ($d)'}. '
            'Vérifiez le réseau, désactivez un éventuel bloqueur de publicités ou '
            'antivirus pour ce site, ou essayez dans une fenêtre privée.',
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
        _models = available.where((m) => m != model).toList();
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'La clé est valide, mais « $model » ne répond pas. ${_explain(e, model)}'
            '${available.isEmpty ? '' : ' Essayez un autre modèle :'}';
        _statusOk = false;
        _models = available.where((m) => m != model).toList();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
