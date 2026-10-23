import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/gemini_client.dart';
import 'package:revis_kids/ai/quest.dart';
import 'package:revis_kids/ai/tutor.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/core/quest_theme.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/game/game_state.dart';
import 'package:revis_kids/features/scan/photo_capture_view.dart';
import 'package:revis_kids/features/tutor/answer_flow_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Curriculum curriculum;

// PNG 1x1 valide : l'aperçu de la photo doit pouvoir la décoder.
final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const quest = Quest(
  enonceTranscrit: 'Calcule 3/4 + 1/4',
  titre: 'Le trésor des quarts',
  scenario: 'Une île mystérieuse.',
  defi: 'Trouve la somme de 3/4 et 1/4.',
  consigneEcriture: 'Écris ta réponse sur ton cahier.',
  confiance: 0.9,
  matiereId: 'mathematiques',
  competenceId: 'MA.FRA.03',
);

const capsuleJson = {
  'titre': 'Additionner des fractions',
  'lecon': 'Quand le dénominateur est le même, on additionne les numérateurs.',
  'a_retenir': 'Même dénominateur : on additionne les numérateurs.',
  'quiz': [
    {
      'question': 'Combien font 2/5 + 1/5 ?',
      'choix': ['3/5', '3/10', '2/5'],
      'bonne_reponse': 0,
    },
    {
      'question': 'Que fait-on du dénominateur ?',
      'choix': ['On l\'additionne', 'On le garde', 'On le supprime'],
      'bonne_reponse': 1,
    },
  ],
};

String verifJson({
  bool correct = false,
  bool incertaine = false,
  bool estReponse = true,
  String message = 'Relis la consigne : que cherches-tu ?',
  String attendue = '1',
}) =>
    jsonEncode({
      'est_une_reponse': estReponse,
      'reponse_lue': '7/8',
      'lecture_incertaine': incertaine,
      'question_de_confirmation': incertaine ? "J'ai lu 7/8, c'est bien ça ?" : '',
      'correct': correct,
      'reponse_attendue': attendue,
      'message': message,
      'erreur_type': 'calcul',
    });

void main() {
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('lecture de la vérification', () {
    test('réponse correcte', () {
      final v = parseVerification(verifJson(correct: true, message: 'Bravo !'));
      expect(v.correct, isTrue);
      expect(v.message, 'Bravo !');
    });

    test('réponse fausse avec indice', () {
      final v = parseVerification(verifJson());
      expect(v.correct, isFalse);
      expect(v.message, contains('Relis'));
    });

    test('pas de réponse écrite sur la photo', () {
      expect(parseVerification('{"est_une_reponse": false}').estUneReponse, isFalse);
    });

    test('lecture incertaine transmise avec sa question', () {
      final v = parseVerification(verifJson(incertaine: true));
      expect(v.lectureIncertaine, isTrue);
      expect(v.questionConfirmation, "J'ai lu 7/8, c'est bien ça ?");
    });

    test('JSON entouré de balises accepté, texte quelconque refusé', () {
      expect(parseVerification('```json\n${verifJson()}\n```').estUneReponse, isTrue);
      expect(() => parseVerification('bonjour'), throwsA(isA<TutorParseException>()));
    });
  });

  group('lecture de la capsule', () {
    test('capsule valide', () {
      final c = parseCapsule(jsonEncode(capsuleJson));
      expect(c.quiz, hasLength(2));
      expect(c.quiz.first.bonneReponse, 0);
    });

    test('quiz absent ou bonne réponse hors choix : refusé', () {
      final sansQuiz = Map<String, dynamic>.from(capsuleJson)..remove('quiz');
      expect(() => parseCapsule(jsonEncode(sansQuiz)), throwsA(isA<TutorParseException>()));

      final mauvais = jsonDecode(jsonEncode(capsuleJson)) as Map<String, dynamic>;
      (mauvais['quiz'] as List)[0]['bonne_reponse'] = 9;
      expect(() => parseCapsule(jsonEncode(mauvais)), throwsA(isA<TutorParseException>()));
    });
  });

  group("filet anti-fuite des indices", () {
    test("un indice qui contient la réponse est remplacé", () {
      final h = safeHint('Pense que le résultat vaut 7/4 au final.', '7/4');
      expect(h, isNot(contains('7/4')));
    });

    test("insensible aux espaces, à la casse et à la virgule décimale", () {
      expect(safeHint('Tu dois trouver 7,5 cm', '7.5'), isNot(contains('7,5')));
      expect(safeHint('Le mot est CHEVAL', 'cheval'), isNot(contains('CHEVAL')));
    });

    test('un bon indice est conservé', () {
      const h = 'Que cherches-tu ? Relis la question.';
      expect(safeHint(h, '7/4'), h);
    });

    test('réponses trop courtes non filtrées, indice vide remplacé', () {
      const h = 'Regarde le 1er nombre de ton calcul.';
      expect(safeHint(h, '1'), h);
      expect(safeHint('   ', '7/4'), isNotEmpty);
    });
  });

  group('requêtes vers Gemini', () {
    http.Response reply(String text) => http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': text},
                  ],
                },
              },
            ],
          })),
          200,
        );

    GeminiClient clientWith(MockClient m) =>
        GeminiClient(apiKey: 'TEST-KEY-123456', model: 'gemini-test', client: m);

    test('vérification : photo jointe, énoncé, interdiction de donner la réponse', () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return reply(verifJson(correct: true, message: 'Bravo !'));
      }));
      final v = await c.verifyAnswer(
        image: Uint8List.fromList([9, 9]),
        mimeType: 'image/png',
        quest: quest,
        competence: curriculum.competence('MA.FRA.03'),
        theme: QuestTheme.histoire,
        attemptNumber: 2,
      );
      expect(v.correct, isTrue);

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final system = body['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains('Calcule 3/4 + 1/4'));
      expect(system, contains('JAMAIS la réponse'));
      expect(system, contains('Niveau d\'indice demandé : 2'));
      expect(system, contains('Histoire de France'));
      final parts = body['contents'][0]['parts'] as List;
      expect(parts.any((p) => p['inlineData']?['mimeType'] == 'image/png'), isTrue);
      expect(seen.headers['x-goog-api-key'], 'TEST-KEY-123456');
      expect(seen.url.toString(), isNot(contains('TEST-KEY')));
    });

    test('capsule : sans photo, avec la compétence, sans résoudre l\'exercice', () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return reply(jsonEncode(capsuleJson));
      }));
      final capsule = await c.createCapsule(
        quest: quest,
        competence: curriculum.competence('MA.FRA.03'),
        theme: QuestTheme.danse,
      );
      expect(capsule.titre, 'Additionner des fractions');

      expect(seen.body, isNot(contains('inlineData')));
      final system = jsonDecode(seen.body)['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains('Additionner et soustraire des fractions'));
      expect(system, contains('exemple différent de l\'exercice'));
      expect(system, contains('2 questions'));
    });

    test('réponse du modèle illisible : erreur propre', () async {
      final c = clientWith(MockClient((_) async => reply('pas du json')));
      await expectLater(
        c.createCapsule(quest: quest, competence: null, theme: QuestTheme.aventures),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.badResponse)),
      );
    });
  });

  group('sans clé enregistrée (vrais fournisseurs)', () {
    Future<ProviderContainer> containerWithoutKey() async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test("la quête échoue tout de suite avec l'erreur « clé absente »", () async {
      final c = await containerWithoutKey();
      await expectLater(
        c.read(questGeneratorProvider.future).timeout(const Duration(seconds: 5)),
        throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.noKey)),
      );
    });

    test("le tuteur échoue tout de suite avec l'erreur « clé absente »", () async {
      final c = await containerWithoutKey();
      await expectLater(
        c.read(tutorServiceProvider.future).timeout(const Duration(seconds: 5)),
        throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.noKey)),
      );
    });
  });

  group('parcours réponse et mode tuteur', () {
    late SharedPreferences prefs;

    Future<(ProviderContainer, _FakeTutor)> openFlow(
      WidgetTester tester,
      List<String> verdicts, {
      Duration minRead = Duration.zero,
      Object? tutorError,
      ProgressState? seedProgress,
    }) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        if (seedProgress != null) 'progress_v1': seedProgress.encode(),
      });
      prefs = await SharedPreferences.getInstance();
      final tutor = _FakeTutor(verdicts);
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        tutorServiceProvider.overrideWith((ref) async {
          if (tutorError != null) throw tutorError;
          return tutor;
        }),
        photoPickerProvider.overrideWithValue(
          ({required bool camera}) async =>
              (bytes: onePixelPng, mimeType: 'image/png'),
        ),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => AnswerFlowScreen(
                quest: quest,
                minRead: minRead,
                minReread: minRead,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      return (container, tutor);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> submitPhoto(WidgetTester tester) async {
      await tester.tap(find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Vérifier ma réponse'));
      await settle(tester);
    }

    Future<List<Attempt>> attemptsOf(ProviderContainer c) async =>
        (await c.read(progressProvider.future)).attempts;

    testWidgets('bonne réponse du premier coup', (tester) async {
      final (c, _) = await openFlow(tester, [verifJson(correct: true, message: 'Bravo, bien additionné !')]);
      await submitPhoto(tester);

      expect(find.text('Défi réussi !'), findsOneWidget);
      expect(find.text('Bravo, bien additionné !'), findsOneWidget);
      final a = await attemptsOf(c);
      expect(a.single.success, isTrue);
      expect(a.single.capsuleRead, isFalse);
      expect(a.single.competenceId, 'MA.FRA.03');
    });

    testWidgets('une réussite du premier coup rapporte XP, étoiles et matériau', (tester) async {
      final (c, _) = await openFlow(tester, [verifJson(correct: true, message: 'Bravo !')]);
      await submitPhoto(tester);

      expect(find.text('+30 XP'), findsOneWidget);
      final g = await c.read(gameProvider.future);
      expect((g.xp, g.stars, g.materialCount('pierre')), (30, 3, 2));
    });

    testWidgets('devenir « acquise » donne le gros bonus', (tester) async {
      DateTime d(int back) => DateTime.now().subtract(Duration(days: back));
      final seed = ProgressState(attempts: [
        Attempt(competenceId: 'MA.FRA.03', date: d(3), success: true),
        Attempt(competenceId: 'MA.FRA.03', date: d(2), success: true),
      ]);
      final (c, _) = await openFlow(
        tester,
        [verifJson(correct: true, message: 'Bravo !')],
        seedProgress: seed,
      );
      await submitPhoto(tester);

      expect(find.textContaining('Notion acquise'), findsOneWidget);
      final g = await c.read(gameProvider.future);
      expect(g.xp, 80);
      expect(g.stars, 8);
    });

    testWidgets('au-delà de 3 réussites le même jour : plus de récompense', (tester) async {
      DateTime today(int hour) {
        final n = DateTime.now();
        return DateTime(n.year, n.month, n.day, 0, hour);
      }

      final seed = ProgressState(attempts: [
        for (var i = 1; i <= 3; i++)
          Attempt(competenceId: 'MA.FRA.03', date: today(i), success: true),
      ]);
      final (c, _) = await openFlow(
        tester,
        [verifJson(correct: true, message: 'Bravo !')],
        seedProgress: seed,
      );
      await submitPhoto(tester);

      expect(find.textContaining("déjà bien travaillé"), findsOneWidget);
      final g = await c.read(gameProvider.future);
      expect((g.xp, g.stars), (0, 0));
    });

    testWidgets("une mauvaise réponse donne un indice, jamais la réponse", (tester) async {
      final (_, tutor) = await openFlow(tester, [
        verifJson(message: 'La réponse est 1, tu as oublié de simplifier.', attendue: 'la réponse est 1, tu'),
      ]);
      await submitPhoto(tester);

      expect(find.textContaining('Pas encore'), findsOneWidget);
      expect(find.textContaining('Il te reste 2 essai'), findsOneWidget);
      expect(find.textContaining('La réponse est 1'), findsNothing);
      expect(find.textContaining('Relis bien la consigne'), findsOneWidget);
      expect(tutor.attemptNumbers, [1]);
    });

    testWidgets("trois échecs : capsule, quiz, puis même défi et réussite", (tester) async {
      final (c, tutor) = await openFlow(tester, [
        verifJson(),
        verifJson(),
        verifJson(),
        verifJson(correct: true, message: 'Bravo !'),
      ]);

      for (var i = 0; i < 2; i++) {
        await submitPhoto(tester);
        expect(find.textContaining('Pas encore'), findsOneWidget);
        await tester.tap(find.text('Je réessaie'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await submitPhoto(tester);

      // Capsule affichée après le 3e échec.
      expect(find.textContaining('Bon à savoir : Additionner des fractions'), findsOneWidget);
      expect(find.textContaining('Même dénominateur'), findsWidgets);
      await tester.tap(find.textContaining("J'ai lu"));
      await tester.pump(const Duration(milliseconds: 50));

      // Quiz : bonnes réponses aux deux questions.
      expect(find.text('Question 1 sur 2'), findsOneWidget);
      await tester.tap(find.text('3/5'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Question 2 sur 2'), findsOneWidget);
      await tester.tap(find.text('On le garde'));
      await tester.pump(const Duration(milliseconds: 50));

      // Retour au même défi.
      expect(find.textContaining('Retente maintenant le même défi'), findsOneWidget);
      expect(find.text('Trouve la somme de 3/4 et 1/4.'), findsOneWidget);
      await submitPhoto(tester);

      expect(find.text('Défi réussi !'), findsOneWidget);
      expect(tutor.capsuleCalls, 1);
      final a = await attemptsOf(c);
      expect(a.map((x) => x.success), [false, false, false, true]);
      expect(a.map((x) => x.capsuleRead), [false, false, false, true]);
    });

    testWidgets('mauvaise réponse au quiz : retour à la capsule', (tester) async {
      await openFlow(tester, [verifJson(), verifJson(), verifJson()]);
      for (var i = 0; i < 2; i++) {
        await submitPhoto(tester);
        await tester.tap(find.text('Je réessaie'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await submitPhoto(tester);
      await tester.tap(find.textContaining("J'ai lu"));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('3/10'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Relis bien la capsule'), findsOneWidget);
      expect(find.textContaining('Bon à savoir'), findsOneWidget);
    });

    testWidgets('la capsule ne peut pas être sautée avant le temps de lecture', (tester) async {
      await openFlow(tester, [verifJson(), verifJson(), verifJson()],
          minRead: const Duration(seconds: 5));
      for (var i = 0; i < 2; i++) {
        await submitPhoto(tester);
        await tester.tap(find.text('Je réessaie'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await submitPhoto(tester);

      FilledButton readButton() => tester.widget<FilledButton>(
            find.ancestor(
              of: find.textContaining('Prends le temps de lire'),
              matching: find.byType(FilledButton),
            ),
          );
      expect(readButton().onPressed, isNull);

      await tester.pump(const Duration(seconds: 6));
      expect(find.textContaining("J'ai lu"), findsOneWidget);
      final enabled = tester.widget<FilledButton>(find.ancestor(
        of: find.textContaining("J'ai lu"),
        matching: find.byType(FilledButton),
      ));
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets("lecture incertaine : on demande confirmation avant de juger", (tester) async {
      final (c, tutor) = await openFlow(tester, [
        verifJson(incertaine: true, correct: true, message: 'Bravo !'),
      ]);
      await submitPhoto(tester);

      expect(find.text("J'ai lu 7/8, c'est bien ça ?"), findsOneWidget);
      expect(await attemptsOf(c), isEmpty);

      // « Non » : on reprend la photo, rien n'est compté.
      await tester.tap(find.text('Non, je reprends la photo'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Vérifier ma réponse'), findsNothing);
      expect(await attemptsOf(c), isEmpty);
      expect(tutor.attemptNumbers, [1]);
    });

    testWidgets("lecture incertaine confirmée : le verdict est appliqué", (tester) async {
      final (c, _) = await openFlow(tester, [
        verifJson(incertaine: true, correct: true, message: 'Bravo !'),
      ]);
      await submitPhoto(tester);
      await tester.tap(find.text("Oui, c'est ça"));
      await settle(tester);

      expect(find.text('Défi réussi !'), findsOneWidget);
      expect((await attemptsOf(c)).single.success, isTrue);
    });

    testWidgets("photo sans réponse écrite : message, aucun essai compté", (tester) async {
      final (c, _) = await openFlow(tester, [verifJson(estReponse: false)]);
      await submitPhoto(tester);

      expect(find.textContaining('Je ne vois pas de réponse écrite'), findsOneWidget);
      expect(await attemptsOf(c), isEmpty);
    });

    testWidgets('clé absente : message pour un parent, pas de bouton Réessayer', (tester) async {
      await openFlow(tester, [], tutorError: GeminiException(GeminiErrorKind.noKey));
      await submitPhoto(tester);

      expect(find.textContaining('Demande à un parent'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });
  });
}

class _FakeTutor implements TutorService {
  _FakeTutor(this._verdicts);

  final List<String> _verdicts;
  final List<int> attemptNumbers = [];
  int capsuleCalls = 0;

  @override
  Future<Verification> verifyAnswer({
    required Uint8List image,
    required String mimeType,
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
    required int attemptNumber,
  }) async {
    attemptNumbers.add(attemptNumber);
    return parseVerification(_verdicts.removeAt(0));
  }

  @override
  Future<Capsule> createCapsule({
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
  }) async {
    capsuleCalls++;
    return parseCapsule(jsonEncode(capsuleJson));
  }
}
