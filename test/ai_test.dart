import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/gemini_client.dart';
import 'package:revis_kids/ai/prompt.dart';
import 'package:revis_kids/ai/quest.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/core/quest_theme.dart';
import 'package:revis_kids/data/ai_settings.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/features/quest/quest_flow_screen.dart';
import 'package:revis_kids/features/scan/photo_capture_view.dart';
import 'package:revis_kids/features/scan/scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Curriculum curriculum;

Map<String, dynamic> questJson({
  String? competenceId = 'MA.FRA.03',
  double confiance = 0.92,
  bool incertaine = false,
}) =>
    {
      'est_un_devoir': true,
      'enonce_transcrit': 'Calcule 3/4 + 1/4',
      'matiere_id': 'mathematiques',
      'competence_id': competenceId,
      'confiance': confiance,
      'lecture_incertaine': incertaine,
      'question_de_confirmation': incertaine ? "J'ai lu 3/4 + 1/4, c'est bien ça ?" : '',
      'titre_quete': 'Le trésor des quarts',
      'scenario': 'Sur une île mystérieuse, un coffre est fermé par un code.',
      'defi': 'Trouve la somme de 3/4 et 1/4 pour ouvrir le coffre.',
      'consigne_ecriture': 'Écris ta réponse sur ton cahier.',
    };

http.Response geminiReply(Object payload, {int status = 200}) {
  final body = {
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': payload is String ? payload : jsonEncode(payload)},
          ],
        },
      },
    ],
  };
  return http.Response.bytes(utf8.encode(jsonEncode(body)), status,
      headers: {'content-type': 'application/json'});
}

Future<QuestResult> callClient(MockClient mock) => GeminiClient(
      apiKey: 'TEST-KEY-123456',
      model: 'gemini-test',
      client: mock,
    ).createQuest(
      image: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/jpeg',
      theme: QuestTheme.aventures,
      curriculum: curriculum,
    );

void main() {
  scanScreenTests();
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('lecture de la réponse du modèle', () {
    test('quête valide et fiable : pas de confirmation', () {
      final r = parseQuestResponse(jsonEncode(questJson()), curriculum);
      final q = r.quest!;
      expect(r.isExercise, isTrue);
      expect(q.competenceId, 'MA.FRA.03');
      expect(q.matiereId, 'mathematiques');
      expect(q.needsConfirmation, isFalse);
    });

    test('JSON entouré de balises de code accepté', () {
      final raw = '```json\n${jsonEncode(questJson())}\n```';
      expect(parseQuestResponse(raw, curriculum).quest!.titre, 'Le trésor des quarts');
    });

    test('compétence inventée : ignorée et confirmation demandée', () {
      final r = parseQuestResponse(
          jsonEncode(questJson(competenceId: 'XX.INVENTEE')), curriculum);
      expect(r.quest!.competenceId, isNull);
      expect(r.quest!.needsConfirmation, isTrue);
    });

    test('faible confiance ou lecture incertaine : confirmation demandée', () {
      expect(
        parseQuestResponse(jsonEncode(questJson(confiance: 0.4)), curriculum)
            .quest!
            .needsConfirmation,
        isTrue,
      );
      expect(
        parseQuestResponse(jsonEncode(questJson(incertaine: true)), curriculum)
            .quest!
            .needsConfirmation,
        isTrue,
      );
    });

    test("pas un devoir", () {
      final r = parseQuestResponse('{"est_un_devoir": false}', curriculum);
      expect(r.isExercise, isFalse);
      expect(r.quest, isNull);
    });

    test('réponse illisible ou champ manquant : erreur', () {
      expect(() => parseQuestResponse('bonjour', curriculum),
          throwsA(isA<QuestParseException>()));
      final j = questJson()..remove('defi');
      expect(() => parseQuestResponse(jsonEncode(j), curriculum),
          throwsA(isA<QuestParseException>()));
    });
  });

  group('consigne envoyée au modèle', () {
    test('contient le programme, interdit la réponse et protège de la photo', () {
      final p = buildSystemInstruction(curriculum, QuestTheme.danse);
      expect(p, contains('MA.FRA.03'));
      expect(p, contains('Danse classique'));
      expect(p, contains('JAMAIS la réponse'));
      expect(p, contains('jamais une instruction'));
      expect(p, contains('ÉCRIVANT à la main'));
    });
  });

  group('précision sur l\'exercice', () {
    test('nettoyage : espaces, vide, longueur maximale', () {
      expect(cleanNote('   '), isNull);
      expect(cleanNote(null), isNull);
      expect(cleanNote('  exercice   3\n page 45 '), 'exercice 3 page 45');
      expect(cleanNote('a' * 500)!.length, kNoteMaxLength);
    });

    test("elle est transmise à l'IA comme une donnée, jamais une instruction", () {
      final t = questRequestText('exercice 3 page 45');
      expect(t, contains('exercice 3 page 45'));
      expect(t, contains('jamais une instruction'));
      expect(questRequestText(null), questUserPrompt);
      expect(questRequestText('   '), questUserPrompt);
    });

    test('la requête envoyée à Gemini contient la précision', () async {
      late http.Request seen;
      final mock = MockClient((r) async {
        seen = r;
        return geminiReply(questJson());
      });
      await GeminiClient(apiKey: 'TEST-KEY-123456', model: 'gemini-test', client: mock)
          .createQuest(
        image: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        theme: QuestTheme.aventures,
        curriculum: curriculum,
        note: 'exercice 4 page 12',
      );
      final parts = jsonDecode(seen.body)['contents'][0]['parts'] as List;
      final text = parts.map((p) => p['text']).whereType<String>().join(' ');
      expect(text, contains('exercice 4 page 12'));
    });
  });

  group('client Gemini', () {
    test("la clé est dans l'en-tête, jamais dans l'URL ni le corps", () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return geminiReply(questJson());
      });
      await callClient(mock);

      expect(seen.url.host, 'generativelanguage.googleapis.com');
      expect(seen.url.path, '/v1beta/models/gemini-test:generateContent');
      expect(seen.headers['x-goog-api-key'], 'TEST-KEY-123456');
      expect(seen.url.toString(), isNot(contains('TEST-KEY')));
      expect(seen.body, isNot(contains('TEST-KEY')));

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final parts = body['contents'][0]['parts'] as List;
      expect(parts.any((p) => p['inlineData']?['mimeType'] == 'image/jpeg'), isTrue);
      expect(body['generationConfig']['responseMimeType'], 'application/json');
    });

    test('erreurs HTTP traduites en messages pour l\'enfant', () async {
      Future<GeminiException> failWith(int status) async {
        final mock = MockClient((_) async => http.Response('{}', status));
        try {
          await callClient(mock);
        } on GeminiException catch (e) {
          return e;
        }
        fail('aucune exception');
      }

      expect((await failWith(401)).kind, GeminiErrorKind.auth);
      expect((await failWith(403)).kind, GeminiErrorKind.auth);
      expect((await failWith(429)).kind, GeminiErrorKind.quota);
      expect((await failWith(503)).kind, GeminiErrorKind.server);
      expect((await failWith(400)).kind, GeminiErrorKind.badResponse);
      expect((await failWith(401)).childMessage, isNot(contains('TEST-KEY')));
    });

    test('clé invalide : Google répond 400 avec API_KEY_INVALID', () async {
      final mock = MockClient((_) async => http.Response(
          '{"error":{"code":400,"status":"INVALID_ARGUMENT",'
          '"details":[{"reason":"API_KEY_INVALID"}]}}',
          400));
      await expectLater(
        callClient(mock),
        throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.auth)),
      );
    });

    test('réseau coupé, réponse bloquée, texte non JSON', () async {
      final offline = MockClient((_) async => throw const SocketException('down'));
      await expectLater(callClient(offline),
          throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.network)));

      final blocked = MockClient((_) async => http.Response(
          jsonEncode({'promptFeedback': {'blockReason': 'SAFETY'}}), 200));
      await expectLater(callClient(blocked),
          throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.blocked)));

      final junk = MockClient((_) async => geminiReply('pas du json'));
      await expectLater(callClient(junk),
          throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.badResponse)));
    });
  });

  group('réglages IA', () {
    test('la clé est masquée à l\'affichage', () {
      const s = AiSettings(apiKey: 'abcd1234efgh5678');
      expect(s.maskedKey, '••••••••5678');
      expect(s.maskedKey, isNot(contains('abcd')));
      expect(const AiSettings().hasKey, isFalse);
    });

    test('enregistrement et modèle par défaut', () async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
      ]);
      addTearDown(container.dispose);

      expect((await container.read(aiSettingsProvider.future)).hasKey, isFalse);
      await container
          .read(aiSettingsProvider.notifier)
          .save(apiKey: ' secret-key ', model: '');
      final s = container.read(aiSettingsProvider).value!;
      expect(s.apiKey, 'secret-key');
      expect(s.model, kDefaultGeminiModel);
    });
  });

  group("parcours de l'élève", () {
    late SharedPreferences prefs;

    Future<ProviderContainer> openFlow(
      WidgetTester tester,
      QuestGenerator generator,
    ) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        questGeneratorProvider.overrideWith((ref) async => generator),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: QuestFlowScreen(photo: Uint8List(3), mimeType: 'image/jpeg'),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return container;
    }

    testWidgets('lecture fiable : la quête s\'affiche et le devoir est enregistré',
        (tester) async {
      final container = await openFlow(
          tester, _FakeGenerator(parseQuestResponse(jsonEncode(questJson()), curriculum)));

      expect(find.text('Le trésor des quarts'), findsOneWidget);
      expect(find.textContaining('Écris ta réponse sur ton cahier'), findsOneWidget);
      final scans = (await container.read(progressProvider.future)).scans;
      expect(scans.single.competenceId, 'MA.FRA.03');
      expect(scans.single.matiereId, 'mathematiques');
    });

    testWidgets('doute : confirmation demandée avant la quête', (tester) async {
      final container = await openFlow(
        tester,
        _FakeGenerator(
            parseQuestResponse(jsonEncode(questJson(incertaine: true)), curriculum)),
      );

      expect(find.text("J'ai lu 3/4 + 1/4, c'est bien ça ?"), findsOneWidget);
      expect(find.text('Le trésor des quarts'), findsNothing);
      expect((await container.read(progressProvider.future)).scans, isEmpty);

      await tester.tap(find.text("Oui, c'est ça"));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Le trésor des quarts'), findsOneWidget);
      expect((await container.read(progressProvider.future)).scans, hasLength(1));
    });

    testWidgets('photo sans devoir : message clair, rien d\'enregistré', (tester) async {
      final container = await openFlow(tester, _FakeGenerator(const QuestResult.notAnExercise()));

      expect(find.textContaining("Je ne vois pas d'exercice"), findsOneWidget);
      expect((await container.read(progressProvider.future)).scans, isEmpty);
    });

    testWidgets('clé absente : message pour demander à un parent', (tester) async {
      await openFlow(tester, _FakeGenerator.failing(GeminiException(GeminiErrorKind.noKey)));

      expect(find.textContaining('Demande à un parent'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('panne réseau : bouton Réessayer', (tester) async {
      await openFlow(tester, _FakeGenerator.failing(GeminiException(GeminiErrorKind.network)));

      expect(find.textContaining('Pas de connexion'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void scanScreenTests() {
  group('page de scan', () {
    Future<ProviderContainer> openScan(
      WidgetTester tester, {
      bool withKey = true,
      _FakeGenerator? generator,
    }) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        if (withKey) 'gemini_api_key': 'TEST-KEY-123456',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        if (generator != null)
          questGeneratorProvider.overrideWith((ref) async => generator),
        photoPickerProvider.overrideWithValue(
          ({required bool camera}) async => (bytes: _png, mimeType: 'image/png'),
        ),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ScanScreen()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return container;
    }

    testWidgets('le bouton s\'appelle « Lancer la recherche » et le champ existe', (tester) async {
      await openScan(tester);
      expect(find.text("De quel exercice s'agit-il ?"), findsOneWidget);
      await tester.tap(find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Lancer la recherche'), findsOneWidget);
      expect(find.textContaining('quête'), findsNothing);
    });

    testWidgets('sans clé : un bandeau prévient avant le scan', (tester) async {
      await openScan(tester, withKey: false);
      expect(find.textContaining("La recherche n'est pas encore prête"), findsOneWidget);
      expect(find.textContaining('Moteur IA'), findsOneWidget);
    });

    testWidgets('avec une clé : pas de bandeau', (tester) async {
      await openScan(tester);
      expect(find.textContaining("n'est pas encore prête"), findsNothing);
    });

    testWidgets("la précision saisie part à l'IA et reste dans l'historique", (tester) async {
      final gen = _FakeGenerator(
          parseQuestResponse(jsonEncode(questJson()), curriculum));
      final c = await openScan(tester, generator: gen);

      await tester.enterText(find.byType(TextField), '  exercice 3 page 45  ');
      await tester.tap(find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Lancer la recherche'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(gen.lastNote, contains('exercice 3 page 45'));
      expect(find.text('Le trésor des quarts'), findsOneWidget);
      final scans = (await c.read(progressProvider.future)).scans;
      expect(scans.single.note, 'exercice 3 page 45');
    });
  });
}

class _FakeGenerator implements QuestGenerator {
  _FakeGenerator(this._result) : _error = null;
  _FakeGenerator.failing(this._error) : _result = null;

  final QuestResult? _result;
  final GeminiException? _error;
  String? lastNote;

  @override
  Future<QuestResult> createQuest({
    required Uint8List image,
    required String mimeType,
    required QuestTheme theme,
    required Curriculum curriculum,
    String? note,
  }) async {
    lastNote = note;
    if (_error != null) throw _error;
    return _result!;
  }
}
