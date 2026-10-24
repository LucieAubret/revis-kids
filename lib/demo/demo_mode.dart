import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/exercise.dart';
import '../ai/quest.dart';
import '../ai/tutor.dart';
import '../core/curriculum.dart';
import '../core/quest_theme.dart';
import '../data/prefs.dart';
import '../dictee/dictee_text.dart';
import 'demo_content.dart';

const _demoKey = 'demo_mode';

/// Mode démo : l'IA est simulée, rien n'est envoyé à Google et les données
/// (points, étoiles, historique) restent séparées de celles de l'enfant.
class DemoModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return prefs.getBool(_demoKey) ?? false;
  }

  Future<void> set(bool value) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_demoKey, value);
    state = AsyncData(value);
  }
}

final demoModeProvider = AsyncNotifierProvider<DemoModeNotifier, bool>(DemoModeNotifier.new);

/// Ce que « répondra l'IA » à une réponse manuscrite, au choix du testeur.
enum DemoVerdict {
  correct('Bonne réponse'),
  incorrect('Mauvaise réponse'),
  unreadable('Écriture illisible');

  const DemoVerdict(this.label);

  final String label;
}

/// Ce que « répondra l'IA » à une dictée écrite, au choix du testeur.
enum DemoDictee {
  perfect('Sans faute'),
  errors('Avec erreurs'),
  unreadable('Écriture illisible');

  const DemoDictee(this.label);

  final String label;
}

class DemoVerdictNotifier extends Notifier<DemoVerdict> {
  @override
  DemoVerdict build() => DemoVerdict.incorrect;

  void choose(DemoVerdict v) => state = v;
}

class DemoDicteeNotifier extends Notifier<DemoDictee> {
  @override
  DemoDictee build() => DemoDictee.errors;

  void choose(DemoDictee v) => state = v;
}

final demoVerdictProvider = NotifierProvider<DemoVerdictNotifier, DemoVerdict>(DemoVerdictNotifier.new);
final demoDicteeProvider = NotifierProvider<DemoDicteeNotifier, DemoDictee>(DemoDicteeNotifier.new);

final demoAiProvider = Provider<DemoAi>((ref) => DemoAi(
      verdict: () => ref.read(demoVerdictProvider),
      dictee: () => ref.read(demoDicteeProvider),
    ));

/// IA simulée : mêmes interfaces que Gemini, contenu intégré. Elle ne lit
/// jamais les photos : le testeur choisit lui-même le résultat.
class DemoAi implements QuestGenerator, TutorService, DicteeService, ExerciseService {
  DemoAi({required this.verdict, required this.dictee});

  final DemoVerdict Function() verdict;
  final DemoDictee Function() dictee;

  // ------------------------------------------------------------ exercices

  Quest _quest(
    Competence c,
    QuestTheme theme,
    ExerciseLevel level, {
    bool uncertain = false,
  }) {
    final ex = demoExercises[c.id] ?? genericDemoExercise(c.titre, c.objectifs.first);
    final suffix = switch (level) {
      ExerciseLevel.facile => " Prends ton temps : tu peux t'aider de ton cours.",
      ExerciseLevel.moyen => '',
      ExerciseLevel.defi => ' Bonus : explique ta méthode en une phrase.',
    };
    return Quest(
      enonceTranscrit: ex.enonce,
      titre: c.titre,
      scenario: demoScenario(theme),
      defi: '${ex.defi}$suffix',
      consigneEcriture: 'Écris ta réponse sur ton cahier.',
      confiance: uncertain ? 0.5 : 1,
      matiereId: c.matiereId,
      competenceId: c.id,
      lectureIncertaine: uncertain,
      questionConfirmation:
          uncertain ? "Mode démo : j'ai lu « ${ex.enonce} », c'est bien ça ?" : null,
    );
  }

  @override
  Future<QuestResult> createQuest({
    Uint8List? image,
    String? mimeType,
    required QuestTheme theme,
    required Curriculum curriculum,
    String? note,
  }) async {
    final text = (note ?? '').toLowerCase();
    String? id;
    for (final (pattern, competenceId) in demoKeywords) {
      if (RegExp(pattern).hasMatch(text) && curriculum.competence(competenceId) != null) {
        id = competenceId;
        break;
      }
    }
    // Sans mot-clé reconnu (ou avec une simple photo), la démo montre le cas
    // « je ne suis pas sûr de ma lecture » pour essayer la confirmation.
    final uncertain = id == null;
    final competence = curriculum.competence(id ?? 'MA.FRA.03')!;
    return QuestResult.quest(_quest(competence, theme, ExerciseLevel.moyen, uncertain: uncertain));
  }

  @override
  Future<Quest> generateExercise({
    required Competence competence,
    required QuestTheme theme,
    required ExerciseLevel level,
  }) async =>
      _quest(competence, theme, level);

  // ---------------------------------------------------------------- tuteur

  @override
  Future<Verification> verifyAnswer({
    required Uint8List image,
    required String mimeType,
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
    required int attemptNumber,
  }) async {
    switch (verdict()) {
      case DemoVerdict.correct:
        return const Verification(
          estUneReponse: true,
          reponseLue: '(simulé)',
          correct: true,
          message: "Bravo, c'est correct ! (Réponse simulée : en mode démo, "
              "l'IA ne lit pas ta photo.)",
        );
      case DemoVerdict.unreadable:
        return const Verification(
          estUneReponse: true,
          reponseLue: '7/8',
          lectureIncertaine: true,
          questionConfirmation: "Mode démo : j'ai lu « 7/8 », c'est bien ça ?",
          correct: true,
          message: 'Bravo, bien réussi ! (Réponse simulée.)',
        );
      case DemoVerdict.incorrect:
        final objectif = competence?.objectifs.first;
        return Verification(
          estUneReponse: true,
          reponseLue: '(simulé)',
          correct: false,
          message: attemptNumber <= 1
              ? 'Relis bien la consigne : que te demande-t-on exactement ? '
                  'Souligne les données importantes avant de recommencer.'
              : 'Pense à ce que tu as appris${competence == null ? '' : ' sur « ${competence.titre} »'}'
                  '${objectif == null ? '' : ' : $objectif'}. '
                  'Refais ton travail étape par étape.',
        );
    }
  }

  @override
  Future<Capsule> createCapsule({
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
  }) async {
    final titre = competence?.titre ?? quest.titre;
    final objectifs = competence?.objectifs ?? const ['Relire la consigne avec attention'];
    final lecon = StringBuffer('Voici ce que le programme de CM1 demande pour « $titre » :');
    for (final o in objectifs.take(4)) {
      lecon.write('\n• $o.');
    }
    const fausseNotions = [
      'Les solides en trois dimensions',
      'La lecture à voix haute avec expressivité',
    ];
    const fauxObjectifs = [
      "Calculer la vitesse d'une voiture de course",
      'Apprendre une chanson en espagnol',
    ];
    // Place la bonne réponse à un endroit qui dépend du titre, pour varier.
    final pos = titre.length % 3;
    List<String> mix(String bonne, List<String> faux) =>
        [...faux.sublist(0, pos.clamp(0, 2)), bonne, ...faux.sublist(pos.clamp(0, 2))];
    final c1 = mix(titre, fausseNotions);
    final c2 = mix(objectifs.first, fauxObjectifs);
    return Capsule(
      titre: titre,
      lecon: lecon.toString(),
      aRetenir: objectifs.first,
      quiz: [
        QuizQuestion(
          question: 'Quelle notion travailles-tu dans cette capsule ?',
          choix: c1,
          bonneReponse: c1.indexOf(titre),
        ),
        QuizQuestion(
          question: 'Quelle phrase fait partie du programme de cette notion ?',
          choix: c2,
          bonneReponse: c2.indexOf(objectifs.first),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- dictée

  @override
  Future<DicteeText> extractText({required Uint8List image, required String mimeType}) async {
    final (titre, texte) = demoDictees[QuestTheme.histoire]!;
    return DicteeText(titre: titre, texte: texte);
  }

  @override
  Future<DicteeText> generateText({
    required QuestTheme theme,
    required Curriculum curriculum,
  }) async {
    final (titre, texte) = demoDictees[theme]!;
    return DicteeText(titre: titre, texte: texte);
  }

  @override
  Future<DicteeCorrection> correct({
    required Uint8List image,
    required String mimeType,
    required String texteSource,
    required Curriculum curriculum,
  }) async {
    final outcome = dictee();
    if (outcome == DemoDictee.perfect) {
      return const DicteeCorrection(
        estUneDictee: true,
        texteLu: '(simulé)',
        competences: [
          DicteeCompetence(id: 'FR.ORT.02', reussie: true),
          DicteeCompetence(id: 'FR.ORT.03', reussie: true),
          DicteeCompetence(id: 'FR.CON.02', reussie: true),
        ],
        message: 'Dictée parfaite, bravo ! (Correction simulée : en mode démo, '
            "l'IA ne lit pas ta photo.)",
      );
    }
    final erreurs = _demoErrors(texteSource, curriculum);
    final categories = erreurs.map((e) => e.categorie).toSet();
    return DicteeCorrection(
      estUneDictee: true,
      lectureIncertaine: outcome == DemoDictee.unreadable,
      questionConfirmation: outcome == DemoDictee.unreadable
          ? "Mode démo : j'ai du mal à lire certains mots. J'ai bien lu ta dictée ?"
          : null,
      texteLu: texteSource.split('. ').first,
      erreurs: erreurs,
      competences: [
        DicteeCompetence(id: 'FR.ORT.02', reussie: !categories.contains(ErrorCategory.accord)),
        const DicteeCompetence(id: 'FR.ORT.03', reussie: true),
        DicteeCompetence(id: 'FR.CON.02', reussie: !categories.contains(ErrorCategory.grammaire)),
      ],
      message: "Tu as bien écrit la plupart des mots, continue ! (Correction simulée : "
          'ces erreurs sont des exemples pour la démonstration.)',
    );
  }

  /// Fabrique trois erreurs plausibles à partir de mots du texte dicté : un
  /// accord, une orthographe d'usage et une terminaison de verbe.
  List<DicteeError> _demoErrors(String source, Curriculum curriculum) {
    final seen = <String>{};
    final words = [
      for (final m in RegExp(r"[A-Za-zÀ-ÿ]+").allMatches(source))
        if (m.group(0)!.length >= 5 && seen.add(m.group(0)!.toLowerCase())) m.group(0)!,
    ];
    if (words.length < 3) return const [];
    final picks = {
      words[words.length ~/ 4],
      words[words.length ~/ 2],
      words[(words.length * 3) ~/ 4],
    }.toList();

    String competence(String id) => curriculum.competence(id) != null ? id : '';
    final out = <DicteeError>[];
    for (var i = 0; i < picks.length; i++) {
      final w = picks[i];
      switch (i) {
        case 0:
          out.add(DicteeError(
            motEcrit: w.endsWith('s') ? w.substring(0, w.length - 1) : '${w}s',
            motAttendu: w,
            categorie: ErrorCategory.accord,
            competenceId: competence('FR.ORT.02'),
            explication: "Vérifie l'accord : ce mot s'accorde avec le nom ou le sujet qu'il accompagne.",
          ));
        case 1:
          out.add(DicteeError(
            motEcrit: w.substring(0, w.length - 3) + w.substring(w.length - 2),
            motAttendu: w,
            categorie: ErrorCategory.lexique,
            competenceId: competence('FR.VOC.04'),
            explication: "L'orthographe de ce mot est à connaître : relis-le lettre par lettre.",
          ));
        default:
          out.add(DicteeError(
            motEcrit: w.endsWith('nt') ? w.substring(0, w.length - 2) : '${w}e',
            motAttendu: w,
            categorie: ErrorCategory.grammaire,
            competenceId: competence('FR.CON.02'),
            explication: 'Regarde la terminaison : la marque de personne du verbe ne '
                "s'écrit pas ainsi.",
          ));
      }
    }
    return [
      for (final e in out)
        DicteeError(
          motEcrit: e.motEcrit,
          motAttendu: e.motAttendu,
          categorie: e.categorie,
          explication: e.explication,
          competenceId: (e.competenceId?.isEmpty ?? true) ? null : e.competenceId,
        ),
    ];
  }
}
