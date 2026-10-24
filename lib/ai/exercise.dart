import '../core/curriculum.dart';
import '../core/quest_theme.dart';
import 'quest.dart';

/// Difficulté d'un exercice proposé pour une notion du programme.
enum ExerciseLevel {
  facile('Facile', 'Pour bien démarrer'),
  moyen('Moyen', 'Le niveau de la classe'),
  defi('Défi', 'Pour aller plus loin');

  const ExerciseLevel(this.label, this.hint);

  final String label;
  final String hint;
}

/// Génération d'un exercice sur une notion précise du programme CM1.
abstract class ExerciseService {
  Future<Quest> generateExercise({
    required Competence competence,
    required QuestTheme theme,
    required ExerciseLevel level,
  });
}

/// Lit l'exercice renvoyé par le modèle. La notion est connue d'avance : elle
/// n'est jamais demandée au modèle, donc jamais mal identifiée.
Quest parseExercise(String raw, Competence competence) {
  final result = parseQuestResponse(
    _withDefaults(raw, competence),
    Curriculum([
      Matiere(id: competence.matiereId, nom: '', domaines: [
        Domaine(id: '', nom: competence.domaineNom, competences: [competence]),
      ]),
    ]),
  );
  final quest = result.quest;
  if (quest == null) throw QuestParseException('Pas un exercice');
  return Quest(
    enonceTranscrit: quest.enonceTranscrit,
    titre: quest.titre,
    scenario: quest.scenario,
    defi: quest.defi,
    consigneEcriture: quest.consigneEcriture,
    confiance: 1,
    matiereId: competence.matiereId,
    competenceId: competence.id,
  );
}

/// Complète la réponse avec les champs que le modèle n'a pas à fournir pour un
/// exercice généré (identifiant de notion, confiance), afin de réutiliser la
/// même lecture que pour un devoir photographié.
String _withDefaults(String raw, Competence c) {
  var s = raw.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(s);
  if (fence != null) s = fence.group(1)!;
  if (!s.startsWith('{')) throw QuestParseException('Réponse illisible');
  final extra = '"competence_id": "${c.id}", "matiere_id": "${c.matiereId}", '
      '"confiance": 1, "est_un_devoir": true, ';
  return '{$extra${s.substring(1)}';
}
