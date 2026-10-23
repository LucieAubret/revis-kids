import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'progress.dart';

const kDefaultGeminiModel = 'gemini-3.8-flash';

const _keyKey = 'gemini_api_key';
const _modelKey = 'gemini_model';

class AiSettings {
  const AiSettings({this.apiKey, this.model = kDefaultGeminiModel});

  final String? apiKey;
  final String model;

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// Affichage masqué : seuls les 4 derniers caractères sont visibles.
  String get maskedKey {
    if (!hasKey) return '';
    final k = apiKey!;
    return k.length <= 4 ? '••••' : '••••••••${k.substring(k.length - 4)}';
  }
}

/// Clé API et modèle, saisis par le parent. La clé reste sur l'appareil, hors
/// du code et de Git. Elle est stockée dans les préférences locales, donc
/// lisible par quiconque contrôle l'appareil ou le navigateur.
class AiSettingsNotifier extends AsyncNotifier<AiSettings> {
  @override
  Future<AiSettings> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return AiSettings(
      apiKey: prefs.getString(_keyKey),
      model: prefs.getString(_modelKey) ?? kDefaultGeminiModel,
    );
  }

  Future<void> save({required String? apiKey, required String model}) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final key = apiKey?.trim();
    final m = model.trim().isEmpty ? kDefaultGeminiModel : model.trim();
    if (key == null || key.isEmpty) {
      await prefs.remove(_keyKey);
    } else {
      await prefs.setString(_keyKey, key);
    }
    await prefs.setString(_modelKey, m);
    state = AsyncData(AiSettings(
      apiKey: (key == null || key.isEmpty) ? null : key,
      model: m,
    ));
  }
}

final aiSettingsProvider =
    AsyncNotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);
