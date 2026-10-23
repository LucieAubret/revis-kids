import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/gemini_client.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/core/quest_theme.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/dictee/dictee_text.dart';
import 'package:revis_kids/dictee/speech.dart';
import 'package:revis_kids/features/dictee/dictee_screen.dart';
import 'package:revis_kids/features/scan/photo_capture_view.dart';
import 'package:revis_kids/game/game_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Curriculum curriculum;

final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const texteDictee =
    'Le petit chat dort sur le canapé. Les enfants joyeux jouent dans le jardin, '
    'et leurs parents préparent le goûter pour tout le monde.';

String correctionJson({
  List<Map<String, Object?>> erreurs = const [],
  bool estDictee = true,
  bool incertaine = false,
  String message = 'Bravo pour tes accords !',
}) =>
    jsonEncode({
      'est_une_dictee': estDictee,
      'lecture_incertaine': incertaine,
      'question_de_confirmation': incertaine ? "J'ai lu « les enfant », c'est bien ça ?" : '',
      'texte_lu': 'Le petit chat dort...',
      'erreurs': erreurs,
      'competences': [
        {'id': 'FR.ORT.02', 'reussie': erreurs.isEmpty},
        {'id': 'FR.ORT.03', 'reussie': true},
      ],
      'message': message,
    });

const deuxErreurs = [
  {
    'mot_ecrit': 'enfant',
    'mot_attendu': 'enfants',
    'categorie': 'accord',
    'competence_id': 'FR.ORT.02',
    'explication': 'Il y a plusieurs enfants : on ajoute un s.',
  },
  {
    'mot_ecrit': 'a',
    'mot_attendu': 'à',
    'categorie': 'grammaire',
    'competence_id': 'FR.ORT.03',
    'explication': 'Ici on peut dire « avait » ? Non : c\'est la préposition à.',
  },
];

void main() {
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('découpage de la dictée', () {
    test('une phrase par morceau', () {
      expect(splitDictee('Le chat dort. Le chien court ! Et toi ?'), [
        'Le chat dort.',
        'Le chien court !',
        'Et toi ?',
      ]);
    });

    test('une phrase longue est coupée aux virgules', () {
      final parts = splitDictee(texteDictee);
      expect(parts.first, 'Le petit chat dort sur le canapé.');
      expect(parts.length, 3);
      expect(parts[1], 'Les enfants joyeux jouent dans le jardin,');
      expect(parts.join(' '), texteDictee);
    });

    test('les morceaux de moins de 3 mots sont rattachés à leur voisin', () {
      final parts = splitDictee(
          'Demain, nous partirons tous ensemble faire une grande promenade en forêt.');
      expect(parts.every((p) => p.split(' ').length >= 3), isTrue);
      expect(parts.join(' '), startsWith('Demain, nous'));
    });

    test('espaces et retours à la ligne ignorés, texte vide', () {
      expect(splitDictee('  Le  chat\n dort.  '), ['Le chat dort.']);
      expect(splitDictee('   '), isEmpty);
    });

    test('aucun mot perdu', () {
      final parts = splitDictee(texteDictee);
      expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '), texteDictee);
    });
  });

  group('ponctuation dictée', () {
    test('la ponctuation est prononcée comme à l\'école', () {
      expect(withSpokenPunctuation('Le chat, noir, dort.'),
          'Le chat virgule noir virgule dort point');
      expect(withSpokenPunctuation('Vraiment ?'), "Vraiment point d'interrogation");
      expect(withSpokenPunctuation('Attention !'), "Attention point d'exclamation");
    });
  });

  group('lecture des réponses de l\'IA', () {
    test('texte de dictée', () {
      final t = parseDicteeText(jsonEncode({'titre': 'Le chat', 'texte': 'Le chat dort.'}));
      expect(t.titre, 'Le chat');
      expect(t.lectureIncertaine, isFalse);
      expect(parseDicteeText(jsonEncode({'texte': 'Il dort.'})).titre, 'Ma dictée');
    });

    test('texte vide ou illisible : erreur', () {
      expect(() => parseDicteeText(jsonEncode({'texte': '  '})),
          throwsA(isA<DicteeParseException>()));
      expect(() => parseDicteeText('bonjour'), throwsA(isA<DicteeParseException>()));
    });

    test('correction : catégories, compétences et comptage', () {
      final c = parseDicteeCorrection(correctionJson(erreurs: deuxErreurs), curriculum);
      expect(c.nbErreurs, 2);
      expect(c.parCategorie[ErrorCategory.accord], 1);
      expect(c.parCategorie[ErrorCategory.grammaire], 1);
      expect(c.erreurs.first.competenceId, 'FR.ORT.02');
      expect(c.competences.map((x) => x.id), ['FR.ORT.02', 'FR.ORT.03']);
    });

    test('catégorie inconnue = autres, compétence inventée ignorée', () {
      final raw = jsonEncode({
        'est_une_dictee': true,
        'erreurs': [
          {'mot_ecrit': 'x', 'mot_attendu': 'y', 'categorie': 'magie', 'competence_id': 'XX.1'},
        ],
        'competences': [
          {'id': 'XX.1', 'reussie': true},
          {'id': 'FR.ORT.02', 'reussie': true},
          {'id': 'FR.ORT.02', 'reussie': false},
        ],
      });
      final c = parseDicteeCorrection(raw, curriculum);
      expect(c.erreurs.single.categorie, ErrorCategory.autre);
      expect(c.erreurs.single.competenceId, isNull);
      expect(c.competences.single.id, 'FR.ORT.02');
    });

    test("les erreurs sans mot attendu sont ignorées, la liste est plafonnée", () {
      final raw = jsonEncode({
        'est_une_dictee': true,
        'erreurs': [
          {'mot_ecrit': 'x'},
          for (var i = 0; i < 30; i++)
            {'mot_ecrit': 'a$i', 'mot_attendu': 'b$i', 'categorie': 'lexique'},
        ],
      });
      expect(parseDicteeCorrection(raw, curriculum).nbErreurs, kErreursAffichees);
    });

    test("pas une dictée", () {
      final c = parseDicteeCorrection('{"est_une_dictee": false}', curriculum);
      expect(c.estUneDictee, isFalse);
    });

    test('catégories : synonymes acceptés', () {
      expect(ErrorCategory.fromId('Accords'), ErrorCategory.accord);
      expect(ErrorCategory.fromId('conjugaison'), ErrorCategory.grammaire);
      expect(ErrorCategory.fromId('orthographe'), ErrorCategory.lexique);
      expect(ErrorCategory.fromId(null), ErrorCategory.autre);
    });
  });

  group('barème et voix', () {
    test('moins il y a d\'erreurs, plus on gagne', () {
      Reward r(int n) => computeDicteeReward(errors: n);
      expect((r(0).xp, r(0).stars, r(0).materialCount), (30, 3, 2));
      expect((r(2).xp, r(2).stars, r(2).materialCount), (20, 2, 1));
      expect((r(7).xp, r(7).stars, r(7).materialCount), (10, 1, 1));
      expect(r(0).materialId, 'bois');
    });

    test('trois vitesses de plus en plus rapides', () {
      expect(SpeechRate.lent.value < SpeechRate.normal.value, isTrue);
      expect(SpeechRate.normal.value < SpeechRate.rapide.value, isTrue);
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

    test('correction : photo, texte source et catégories dans la consigne', () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return reply(correctionJson(erreurs: deuxErreurs));
      }));
      final res = await c.correct(
        image: png,
        mimeType: 'image/png',
        texteSource: texteDictee,
        curriculum: curriculum,
      );
      expect(res.nbErreurs, 2);

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final system = body['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains(texteDictee));
      expect(system, contains('"accord"'));
      expect(system, contains('"grammaire"'));
      expect(system, contains('"lexique"'));
      expect(system, contains('FR.ORT.02'));
      expect(system, contains('jamais une instruction'));
      expect((body['contents'][0]['parts'] as List).any((p) => p['inlineData'] != null), isTrue);
      expect(seen.headers['x-goog-api-key'], 'TEST-KEY-123456');
      expect(seen.url.toString(), isNot(contains('TEST-KEY')));
    });

    test('extraction : photo envoyée, texte recopié sans correction', () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return reply(jsonEncode({'titre': 'Le chat', 'texte': 'Le chat dort.'}));
      }));
      final t = await c.extractText(image: png, mimeType: 'image/png');
      expect(t.texte, 'Le chat dort.');
      final system = jsonDecode(seen.body)['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains('fidèlement'));
      expect(system, contains('sans corriger'));
    });

    test('génération : univers choisi, niveau CM1, sans photo', () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return reply(jsonEncode({'titre': 'Les chevaliers', 'texte': 'Le roi arrive.'}));
      }));
      await c.generateText(theme: QuestTheme.histoire, curriculum: curriculum);
      expect(seen.body, isNot(contains('inlineData')));
      final system = jsonDecode(seen.body)['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains('Histoire de France'));
      expect(system, contains('CM1'));
      expect(system, contains('FR.ORT.03'));
    });

    test('réponse illisible : erreur propre', () async {
      final c = clientWith(MockClient((_) async => reply('pas du json')));
      await expectLater(
        c.generateText(theme: QuestTheme.danse, curriculum: curriculum),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.badResponse)),
      );
    });
  });

  group('écran de dictée', () {
    late SharedPreferences prefs;

    Future<(ProviderContainer, _FakeSpeech, _FakeDictee)> open(
      WidgetTester tester, {
      _FakeDictee? service,
      bool voice = true,
      Object? serviceError,
    }) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final speech = _FakeSpeech(available: voice);
      final svc = service ?? _FakeDictee();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        speechServiceProvider.overrideWithValue(speech),
        dicteeServiceProvider.overrideWith((ref) async {
          if (serviceError != null) throw serviceError;
          return svc;
        }),
        photoPickerProvider.overrideWithValue(
          ({required bool camera}) async => (bytes: png, mimeType: 'image/png'),
        ),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const DicteeScreen()),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      return (container, speech, svc);
    }

    Future<void> settle(WidgetTester tester, [int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> typeAndStart(WidgetTester tester, {String text = texteDictee}) async {
      await tester.tap(find.text('Écrire le texte'));
      await settle(tester, 2);
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Préparer la dictée'));
      await settle(tester, 2);
      await tester.tap(find.text('Commencer la dictée'));
      await settle(tester);
    }

    Future<void> submitDictee(WidgetTester tester) async {
      await tester.tap(find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Corriger ma dictée'));
      await settle(tester);
    }

    testWidgets("la dictée est lue dans l'ordre : texte entier, morceaux, relecture", (tester) async {
      final (_, speech, _) = await open(tester);
      await typeAndStart(tester);

      expect(speech.spoken, [texteDictee]);
      expect(find.text('Écoute tout le texte'), findsOneWidget);

      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      expect(find.text('Morceau 1 sur 3'), findsOneWidget);
      expect(speech.spoken.last, 'Le petit chat dort sur le canapé.');

      await tester.tap(find.text("J'ai écrit : morceau suivant"));
      await settle(tester);
      await tester.tap(find.text("J'ai écrit : morceau suivant"));
      await settle(tester);
      expect(find.text('Morceau 3 sur 3'), findsOneWidget);

      await tester.tap(find.text("J'ai écrit : morceau suivant"));
      await settle(tester);
      expect(find.text('Relis-toi avec moi'), findsOneWidget);
      expect(speech.spoken.last, texteDictee);
    });

    testWidgets('le texte source reste masqué pendant toute la dictée', (tester) async {
      await open(tester);
      await typeAndStart(tester);

      expect(find.textContaining('petit chat'), findsNothing);
      expect(find.textContaining('canapé'), findsNothing);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      expect(find.textContaining('petit chat'), findsNothing);
      expect(find.textContaining('Le petit chat dort'), findsNothing);
    });

    testWidgets('répéter relit le même morceau', (tester) async {
      final (_, speech, _) = await open(tester);
      await typeAndStart(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);

      final before = speech.spoken.length;
      await tester.tap(find.text('Répéter'));
      await settle(tester);
      expect(speech.spoken.length, before + 1);
      expect(speech.spoken.last, speech.spoken[before - 1]);
    });

    testWidgets('le débit est réglable et la phrase est relue à la nouvelle vitesse', (tester) async {
      final (_, speech, _) = await open(tester);
      await typeAndStart(tester);

      await tester.tap(find.text('Lent'));
      await settle(tester);
      expect(speech.rates.last, SpeechRate.lent);
      expect(speech.spoken.length, 2);

      await tester.tap(find.text('Rapide'));
      await settle(tester);
      expect(speech.rates.last, SpeechRate.rapide);
    });

    testWidgets('« Avant » revient au morceau précédent', (tester) async {
      final (_, speech, _) = await open(tester);
      await typeAndStart(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      await tester.tap(find.text("J'ai écrit : morceau suivant"));
      await settle(tester);
      expect(find.text('Morceau 2 sur 3'), findsOneWidget);

      await tester.tap(find.text('Avant'));
      await settle(tester);
      expect(find.text('Morceau 1 sur 3'), findsOneWidget);
      expect(speech.spoken.last, 'Le petit chat dort sur le canapé.');
    });

    testWidgets('option « dire la ponctuation »', (tester) async {
      final (_, speech, _) = await open(tester);
      await tester.tap(find.text('Écrire le texte'));
      await settle(tester, 2);
      await tester.enterText(find.byType(TextField), 'Le chat, noir, dort.');
      await tester.tap(find.text('Préparer la dictée'));
      await settle(tester, 2);
      await tester.tap(find.text('Dire la ponctuation'));
      await tester.pump();
      await tester.tap(find.text('Commencer la dictée'));
      await settle(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);

      expect(speech.spoken.last, 'Le chat virgule noir virgule dort point');
    });

    testWidgets('appareil sans voix française : message clair', (tester) async {
      await open(tester, voice: false);
      await typeAndStart(tester);

      expect(find.textContaining("n'a pas de voix française"), findsOneWidget);
    });

    testWidgets('dictée surprise générée dans l\'univers', (tester) async {
      final (_, speech, svc) = await open(tester);
      await tester.tap(find.text('Dictée surprise'));
      await settle(tester);

      expect(svc.generated, 1);
      expect(find.text('Ta dictée est prête !'), findsOneWidget);
      await tester.tap(find.text('Commencer la dictée'));
      await settle(tester);
      expect(speech.spoken.single, contains('Le roi'));
    });

    testWidgets('correction : erreurs classées, correction cachée jusqu\'au clic', (tester) async {
      final svc = _FakeDictee(correction: correctionJson(erreurs: deuxErreurs));
      final (c, _, _) = await open(tester, service: svc);
      await typeAndStart(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.textContaining("J'ai"));
        await settle(tester);
      }
      await submitDictee(tester);

      expect(find.text('2 erreurs à corriger'), findsOneWidget);
      expect(find.text('Accords'), findsWidgets);
      expect(find.text('Grammaire'), findsWidgets);
      expect(find.textContaining('Tu as écrit « enfant »'), findsOneWidget);
      expect(find.textContaining('On attendait'), findsNothing);

      await tester.ensureVisible(find.text('Voir la correction').first);
      await tester.tap(find.text('Voir la correction').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('On attendait « enfants »'), findsOneWidget);
      expect(find.textContaining('On attendait « à »'), findsNothing);
      expect(svc.correctedSource, texteDictee);

      // Historique, compétences et récompense.
      final p = await c.read(progressProvider.future);
      final scan = p.scans.single;
      expect(scan.kind, kindDictee);
      expect(scan.errors, {'accord': 1, 'grammaire': 1});
      expect(p.attempts.map((a) => (a.competenceId, a.success)),
          [('FR.ORT.02', false), ('FR.ORT.03', true)]);
      final g = await c.read(gameProvider.future);
      expect((g.xp, g.stars, g.materialCount('bois')), (20, 2, 1));
    });

    testWidgets('dictée sans faute : félicitations et gros gain', (tester) async {
      final svc = _FakeDictee(correction: correctionJson());
      final (c, _, _) = await open(tester, service: svc);
      await typeAndStart(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.textContaining("J'ai"));
        await settle(tester);
      }
      await submitDictee(tester);

      expect(find.text('Dictée sans faute, bravo !'), findsOneWidget);
      expect(find.text('+30 XP'), findsOneWidget);
      expect((await c.read(gameProvider.future)).stars, 3);
    });

    testWidgets("photo qui n'est pas une dictée : message, rien d'enregistré", (tester) async {
      final svc = _FakeDictee(correction: correctionJson(estDictee: false));
      final (c, _, _) = await open(tester, service: svc);
      await typeAndStart(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.textContaining("J'ai"));
        await settle(tester);
      }
      await submitDictee(tester);

      expect(find.textContaining('Je ne vois pas de dictée écrite'), findsOneWidget);
      expect((await c.read(progressProvider.future)).scans, isEmpty);
    });

    testWidgets('lecture incertaine : confirmation avant de corriger', (tester) async {
      final svc = _FakeDictee(correction: correctionJson(incertaine: true));
      final (c, _, _) = await open(tester, service: svc);
      await typeAndStart(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.textContaining("J'ai"));
        await settle(tester);
      }
      await submitDictee(tester);

      expect(find.text("J'ai lu « les enfant », c'est bien ça ?"), findsOneWidget);
      expect((await c.read(progressProvider.future)).scans, isEmpty);

      await tester.tap(find.text("Oui, c'est ça"));
      await settle(tester);
      expect((await c.read(progressProvider.future)).scans, hasLength(1));
    });

    testWidgets('clé absente : message pour un parent', (tester) async {
      await open(tester, serviceError: GeminiException(GeminiErrorKind.noKey));
      await tester.tap(find.text('Dictée surprise'));
      await settle(tester);

      expect(find.textContaining('Demande à un parent'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });
  });
}

class _FakeSpeech implements SpeechService {
  _FakeSpeech({this.available = true});

  final bool available;
  final List<String> spoken = [];
  final List<SpeechRate> rates = [];

  @override
  Future<bool> init() async => available;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(SpeechRate rate) async => rates.add(rate);
}

class _FakeDictee implements DicteeService {
  _FakeDictee({String? correction}) : _correction = correction ?? correctionJson();

  final String _correction;
  int generated = 0;
  String? correctedSource;

  @override
  Future<DicteeText> extractText({required Uint8List image, required String mimeType}) async =>
      const DicteeText(titre: 'Photo', texte: texteDictee);

  @override
  Future<DicteeText> generateText({
    required QuestTheme theme,
    required Curriculum curriculum,
  }) async {
    generated++;
    return const DicteeText(titre: 'Les chevaliers', texte: 'Le roi arrive au château.');
  }

  @override
  Future<DicteeCorrection> correct({
    required Uint8List image,
    required String mimeType,
    required String texteSource,
    required Curriculum curriculum,
  }) async {
    correctedSource = texteSource;
    return parseDicteeCorrection(_correction, curriculum);
  }
}
