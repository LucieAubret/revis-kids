import 'dart:convert';

import '../core/curriculum.dart';

/// Quête scénarisée construite par l'IA à partir de la photo d'un devoir.
class Quest {
  const Quest({
    required this.enonceTranscrit,
    required this.titre,
    required this.scenario,
    required this.defi,
    required this.consigneEcriture,
    required this.confiance,
    this.matiereId,
    this.competenceId,
    this.lectureIncertaine = false,
    this.questionConfirmation,
  });

  final String enonceTranscrit;
  final String titre;
  final String scenario;
  final String defi;
  final String consigneEcriture;
  final double confiance;
  final String? matiereId;
  final String? competenceId;
  final bool lectureIncertaine;
  final String? questionConfirmation;

  /// En cas de doute, l'app demande à l'élève de confirmer avant de continuer.
  bool get needsConfirmation =>
      lectureIncertaine || confiance < kSeuilConfiance || competenceId == null;
}

const double kSeuilConfiance = 0.75;

class QuestParseException implements Exception {
  QuestParseException(this.message);
  final String message;
  @override
  String toString() => 'QuestParseException: $message';
}

/// Résultat de l'analyse : soit un devoir exploitable, soit « pas un devoir ».
class QuestResult {
  const QuestResult.notAnExercise()
      : quest = null,
        isExercise = false;
  const QuestResult.quest(Quest this.quest) : isExercise = true;

  final bool isExercise;
  final Quest? quest;
}

String _extractJson(String raw) {
  var s = raw.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
  final m = fence.firstMatch(s);
  if (m != null) s = m.group(1)!;
  return s;
}

String _str(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.trim().isEmpty) {
    throw QuestParseException('Champ manquant ou vide : $key');
  }
  return v.trim();
}

/// Lit la réponse JSON du modèle. Les identifiants inconnus du référentiel
/// sont ignorés (la quête demandera alors une confirmation).
QuestResult parseQuestResponse(String raw, Curriculum curriculum) {
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(_extractJson(raw)) as Map<String, dynamic>;
  } catch (_) {
    throw QuestParseException('Réponse illisible');
  }

  if (j['est_un_devoir'] == false) return const QuestResult.notAnExercise();

  final competenceId = j['competence_id'] as String?;
  final competence = competenceId == null ? null : curriculum.competence(competenceId);
  final matiereId = competence?.matiereId ??
      ((j['matiere_id'] is String && curriculum.matiere(j['matiere_id'] as String) != null)
          ? j['matiere_id'] as String
          : null);

  final confianceRaw = j['confiance'];
  final confiance = confianceRaw is num ? confianceRaw.toDouble().clamp(0.0, 1.0) : 0.0;

  return QuestResult.quest(Quest(
    enonceTranscrit: _str(j, 'enonce_transcrit'),
    titre: _str(j, 'titre_quete'),
    scenario: _str(j, 'scenario'),
    defi: _str(j, 'defi'),
    consigneEcriture: _str(j, 'consigne_ecriture'),
    confiance: confiance,
    matiereId: matiereId,
    competenceId: competence?.id,
    lectureIncertaine: j['lecture_incertaine'] == true,
    questionConfirmation: (j['question_de_confirmation'] as String?)?.trim(),
  ));
}
