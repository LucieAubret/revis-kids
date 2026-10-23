import 'dart:convert';
import 'dart:typed_data';

import '../core/curriculum.dart';
import '../core/quest_theme.dart';
import 'quest.dart';

/// Nombre d'essais avant que la capsule « Bon à savoir » soit proposée.
const int kEssaisAvantCapsule = 3;

/// Verdict de l'IA sur la réponse manuscrite photographiée.
class Verification {
  const Verification({
    required this.estUneReponse,
    this.reponseLue = '',
    this.lectureIncertaine = false,
    this.questionConfirmation,
    this.correct = false,
    this.message = '',
    this.reponseAttendue,
    this.typeErreur,
  });

  /// La photo montre bien une réponse écrite.
  final bool estUneReponse;
  final String reponseLue;
  final bool lectureIncertaine;
  final String? questionConfirmation;
  final bool correct;

  /// Félicitation si correct, sinon indice. Jamais la réponse.
  final String message;

  /// Donnée interne servant uniquement à filtrer les indices : jamais affichée.
  final String? reponseAttendue;
  final String? typeErreur;
}

/// Une question de contrôle portant sur la capsule.
class QuizQuestion {
  const QuizQuestion({
    required this.question,
    required this.choix,
    required this.bonneReponse,
  });

  final String question;
  final List<String> choix;
  final int bonneReponse;
}

/// Capsule « Bon à savoir » : rappel de leçon suivi d'un contrôle de lecture.
class Capsule {
  const Capsule({
    required this.titre,
    required this.lecon,
    required this.aRetenir,
    required this.quiz,
  });

  final String titre;
  final String lecon;
  final String aRetenir;
  final List<QuizQuestion> quiz;
}

/// Ce dont l'interface a besoin du tuteur : remplaçable dans les tests.
abstract class TutorService {
  Future<Verification> verifyAnswer({
    required Uint8List image,
    required String mimeType,
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
    required int attemptNumber,
  });

  Future<Capsule> createCapsule({
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
  });
}

class TutorParseException implements Exception {
  TutorParseException(this.message);
  final String message;
  @override
  String toString() => 'TutorParseException: $message';
}

String _extractJson(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(s);
  return m != null ? m.group(1)! : s;
}

Map<String, dynamic> _decode(String raw) {
  try {
    return jsonDecode(_extractJson(raw)) as Map<String, dynamic>;
  } catch (_) {
    throw TutorParseException('Réponse illisible');
  }
}

String _req(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.trim().isEmpty) {
    throw TutorParseException('Champ manquant ou vide : $key');
  }
  return v.trim();
}

Verification parseVerification(String raw) {
  final j = _decode(raw);
  if (j['est_une_reponse'] == false) {
    return const Verification(estUneReponse: false);
  }
  final correct = j['correct'] == true;
  final String message;
  try {
    message = _req(j, 'message');
  } on TutorParseException {
    // Un message vide ne doit pas bloquer l'élève : on prévoit un texte neutre.
    return Verification(
      estUneReponse: true,
      reponseLue: (j['reponse_lue'] as String?)?.trim() ?? '',
      lectureIncertaine: j['lecture_incertaine'] == true,
      questionConfirmation: (j['question_de_confirmation'] as String?)?.trim(),
      correct: correct,
      message: correct ? 'Bravo, bonne réponse !' : '',
      reponseAttendue: (j['reponse_attendue'] as String?)?.trim(),
      typeErreur: (j['erreur_type'] as String?)?.trim(),
    );
  }
  return Verification(
    estUneReponse: true,
    reponseLue: (j['reponse_lue'] as String?)?.trim() ?? '',
    lectureIncertaine: j['lecture_incertaine'] == true,
    questionConfirmation: (j['question_de_confirmation'] as String?)?.trim(),
    correct: correct,
    message: message,
    reponseAttendue: (j['reponse_attendue'] as String?)?.trim(),
    typeErreur: (j['erreur_type'] as String?)?.trim(),
  );
}

Capsule parseCapsule(String raw) {
  final j = _decode(raw);
  final quizRaw = j['quiz'];
  if (quizRaw is! List || quizRaw.isEmpty) {
    throw TutorParseException('Quiz manquant');
  }
  final quiz = <QuizQuestion>[];
  for (final q in quizRaw) {
    if (q is! Map<String, dynamic>) throw TutorParseException('Question invalide');
    final choix = q['choix'];
    final bonne = q['bonne_reponse'];
    if (choix is! List || choix.length < 2 || choix.any((c) => c is! String)) {
      throw TutorParseException('Choix invalides');
    }
    if (bonne is! int || bonne < 0 || bonne >= choix.length) {
      throw TutorParseException('Bonne réponse invalide');
    }
    quiz.add(QuizQuestion(
      question: _req(q, 'question'),
      choix: List<String>.from(choix),
      bonneReponse: bonne,
    ));
  }
  return Capsule(
    titre: _req(j, 'titre'),
    lecon: _req(j, 'lecon'),
    aRetenir: _req(j, 'a_retenir'),
    quiz: quiz,
  );
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');

/// Filet de sécurité : si l'indice contient la réponse attendue, on le remplace
/// par un indice neutre plutôt que de la dévoiler. Les réponses trop courtes
/// (moins de 3 caractères) ne sont pas filtrées : trop de faux positifs.
String safeHint(String hint, String? expected) {
  const neutral =
      'Relis bien la consigne, puis refais ton travail étape par étape. '
      'Tu peux y arriver !';
  if (hint.trim().isEmpty) return neutral;
  if (expected == null) return hint;
  final e = _normalize(expected);
  if (e.length < 3) return hint;
  return _normalize(hint).contains(e) ? neutral : hint;
}
