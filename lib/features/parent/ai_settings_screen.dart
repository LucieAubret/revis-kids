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

  Future<void> _test() async {
    final current = ref.read(aiSettingsProvider).value;
    final typed = sanitizeApiKey(_keyCtrl.text);
    final key = typed.isEmpty ? current?.apiKey : typed;
    if (key == null || key.isEmpty) {
      setState(() {
        _status = "Saisissez d'abord une clé.";
        _statusOk = false;
      });
      return;
    }
    final model = _modelCtrl.text.trim().isEmpty ? kDefaultGeminiModel : _modelCtrl.text.trim();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await GeminiClient(apiKey: key, model: model).testConnection();
      if (!mounted) return;
      setState(() {
        _status = 'Connexion réussie.';
        _statusOk = true;
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        final d = e.detail;
        _status = switch (e.kind) {
          GeminiErrorKind.invalidKey =>
            'La clé contient des caractères non valides (espace, retour à la ligne, '
                'guillemets…). Copiez-la à nouveau, sans rien autour.',
          GeminiErrorKind.auth => 'Clé refusée par Google. Vérifiez-la.',
          GeminiErrorKind.quota => 'Quota atteint. Réessayez plus tard.',
          GeminiErrorKind.modelNotFound =>
            'Le modèle « ${d ?? model} » est introuvable avec cette clé. '
                'Remplacez-le par $kDefaultGeminiModel.',
          GeminiErrorKind.network =>
            'Google est injoignable depuis cet appareil${d == null ? '' : ' ($d)'}. '
                'Vérifiez le réseau, désactivez un éventuel bloqueur de publicités ou '
                'antivirus pour ce site, ou essayez dans une fenêtre privée.',
          GeminiErrorKind.unknown =>
            'Erreur inattendue${d == null ? '' : ' ($d)'}. Signalez-la telle quelle.',
          _ => 'Le test a échoué (${e.kind.name}${d == null ? '' : ', $d'}).',
        };
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
