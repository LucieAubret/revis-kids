import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/exercise.dart';
import 'package:revis_kids/ai/gemini_client.dart';
import 'package:revis_kids/ai/prompt.dart';
import 'package:revis_kids/ai/quest.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/core/quest_theme.dart';
import 'package:revis_kids/core/universe_missions.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/features/exercices/exercices_screen.dart';
import 'package:revis_kids/features/universe/universe_screen.dart';
import 'package:revis_kids/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Curriculum curriculum;

String exerciseJson() => jsonEncode({
      'titre_quete': 'Les fractions du ballet',
      'scenario': 'Les danseuses se rangent sur scène.',
      'enonce_transcrit': 'Calcule les 3/4 de 20.',
      'defi': 'Sur scène, 20 danseuses : les trois quarts portent un tutu rose. Combien ?',
      'consigne_ecriture': 'Écris ta réponse sur ton cahier.',
    });

class _FakeExercises implements ExerciseService {
  final List<(String, ExerciseLevel, QuestTheme)> calls = [];

  @override
  Future<Quest> generateExercise({
    required Competence competence,
    required QuestTheme theme,
    required ExerciseLevel level,
  }) async {
    calls.add((competence.id, level, theme));
    return parseExercise(exerciseJson(), competence);
  }
}

void main() {
  orauxTests();
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('missions des univers', () {
    test('toutes les notions citées existent dans le programme', () {
      for (final entry in universes.entries) {
        for (final m in entry.value.missions) {
          expect(curriculum.competence(m.competenceId), isNotNull,
              reason: '${entry.key.name} : ${m.competenceId}');
        }
      }
    });

    test('chaque univers a une histoire et au moins 6 missions variées', () {
      for (final theme in QuestTheme.values) {
        final info = universes[theme]!;
        expect(info.pitch.length, greaterThan(60), reason: theme.name);
        expect(info.missions.length, greaterThanOrEqualTo(6), reason: theme.name);
        final matieres = info.missions
            .map((m) => curriculum.competence(m.competenceId)!.matiereId)
            .toSet();
        expect(matieres.length, greaterThanOrEqualTo(3), reason: theme.name);
      }
    });
  });

  group('lecture d\'un exercice généré', () {
    test('la notion est imposée, jamais devinée par le modèle', () {
      final c = curriculum.competence('MA.FRA.04')!;
      final q = parseExercise(exerciseJson(), c);
      expect(q.competenceId, 'MA.FRA.04');
      expect(q.matiereId, 'mathematiques');
      expect(q.confiance, 1);
      expect(q.needsConfirmation, isFalse);
      expect(q.titre, 'Les fractions du ballet');
    });

    test('JSON entouré de balises accepté', () {
      final c = curriculum.competence('MA.FRA.04')!;
      expect(parseExercise('```json\n${exerciseJson()}\n```', c).defi, contains('danseuses'));
    });

    test('champ manquant ou texte illisible : erreur', () {
      final c = curriculum.competence('MA.FRA.04')!;
      expect(() => parseExercise('bonjour', c), throwsA(isA<QuestParseException>()));
      final j = jsonDecode(exerciseJson()) as Map<String, dynamic>..remove('defi');
      expect(() => parseExercise(jsonEncode(j), c), throwsA(isA<QuestParseException>()));
    });
  });

  group('requête d\'exercice vers Gemini', () {
    test('notion, objectifs, niveau, univers et interdiction de la réponse', () async {
      late http.Request seen;
      final client = GeminiClient(
        apiKey: 'TEST-KEY-123456',
        model: 'gemini-test',
        client: MockClient((r) async {
          seen = r;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': exerciseJson()},
                    ],
                  },
                },
              ],
            })),
            200,
          );
        }),
      );
      final c = curriculum.competence('MA.FRA.04')!;
      final q = await client.generateExercise(
        competence: c,
        theme: QuestTheme.danse,
        level: ExerciseLevel.defi,
      );
      expect(q.competenceId, 'MA.FRA.04');

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      final system = body['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains(c.titre));
      expect(system, contains(c.objectifs.first));
      expect(system, contains('DÉFI'));
      expect(system, contains('Danse classique'));
      expect(system, contains('JAMAIS la réponse'));
      expect(seen.body, isNot(contains('inlineData')));
      expect(seen.headers['x-goog-api-key'], 'TEST-KEY-123456');
    });

    test('les trois niveaux donnent des consignes différentes', () {
      final c = curriculum.competence('MA.FRA.04')!;
      String p(ExerciseLevel l) => buildExerciseInstruction(
            competence: c,
            theme: QuestTheme.aventures,
            level: l,
            variation: 1,
          );
      expect(p(ExerciseLevel.facile), contains('FACILE'));
      expect(p(ExerciseLevel.moyen), contains('MOYEN'));
      expect(p(ExerciseLevel.defi), contains('DÉFI'));
      expect({p(ExerciseLevel.facile), p(ExerciseLevel.moyen), p(ExerciseLevel.defi)}.length, 3);
    });

    test('la variation change à chaque appel pour éviter les exercices identiques', () {
      final c = curriculum.competence('MA.FRA.04')!;
      String p(int v) => buildExerciseInstruction(
            competence: c,
            theme: QuestTheme.aventures,
            level: ExerciseLevel.moyen,
            variation: v,
          );
      expect(p(1), isNot(p(2)));
    });
  });

  group('écrans', () {
    Future<(ProviderContainer, _FakeExercises)> open(
      WidgetTester tester,
      Widget home, {
      ProgressState? progress,
    }) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        'gemini_api_key': 'TEST-KEY-123456',
        if (progress != null) 'progress_v1': progress.encode(),
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = _FakeExercises();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        exerciseServiceProvider.overrideWith((ref) async => svc),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ref.watch(questThemeProvider).toThemeData(),
            home: home,
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return (container, svc);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('Mes exercices : les six matières avec leur avancement', (tester) async {
      DateTime d(int back) => DateTime.now().subtract(Duration(days: back));
      final progress = ProgressState(attempts: [
        for (var i = 1; i <= 3; i++)
          Attempt(competenceId: 'FR.ORT.02', date: d(i), success: true),
      ]);
      await open(tester, const ExercicesScreen(), progress: progress);

      for (final nom in ['Français', 'Mathématiques', 'Histoire', 'Géographie', 'Anglais', 'Sciences et technologie']) {
        expect(find.text(nom), findsWidgets, reason: nom);
      }
      expect(find.text('1 / 26 acquises'), findsOneWidget);
      expect(find.text('0 / 34 acquises'), findsOneWidget);
    });

    testWidgets('les notions sont rangées par section du programme', (tester) async {
      await open(tester, const ExercicesScreen());

      // Français est sélectionné par défaut : ses sections apparaissent
      // (la liste est paresseuse : on la fait défiler jusqu'à chacune).
      expect(find.text('Lecture'), findsOneWidget);
      expect(find.text('Lire avec fluidité'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Vocabulaire'), 300);
      expect(find.text('Vocabulaire'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Orthographe grammaticale'), 300);
      expect(find.text('Orthographe grammaticale'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Mathématiques'), -300);
      await tester.tap(find.text('Mathématiques'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Nombres entiers'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Espace et géométrie'), 400);
      expect(find.text('Espace et géométrie'), findsOneWidget);
    });

    testWidgets('toucher une notion génère un exercice au niveau choisi', (tester) async {
      final (c, svc) = await open(tester, const ExercicesScreen(matiereId: 'mathematiques'));

      await tester.tap(find.text('Défi'));
      await tester.pump(const Duration(milliseconds: 100));
      // Titre exact de la compétence MA.FRA.04.
      final target = find.text("Fraction d'une quantité ou d'une grandeur");
      await tester.scrollUntilVisible(target, 300);
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(target);
      await settle(tester);

      expect(svc.calls.single.$1, 'MA.FRA.04');
      expect(svc.calls.single.$2, ExerciseLevel.defi);
      expect(find.text('Les fractions du ballet'), findsOneWidget);
      expect(find.textContaining('Écris ta réponse sur ton cahier'), findsOneWidget);

      final scan = (await c.read(progressProvider.future)).scans.single;
      expect(scan.kind, kindExercice);
      expect(scan.competenceId, 'MA.FRA.04');
      expect(scan.matiereId, 'mathematiques');
    });

    testWidgets("la page d'un univers montre son histoire et ses missions", (tester) async {
      await open(tester, const UniverseScreen(theme: QuestTheme.histoire));

      expect(find.textContaining('château du Moyen Âge'), findsOneWidget);
      expect(find.text('Tes missions'), findsOneWidget);
      expect(find.text('Visite le château et rencontre le seigneur'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Voir tout le programme par matière'), 400);
      expect(find.text('Voir tout le programme par matière'), findsOneWidget);
    });

    testWidgets("toucher une mission lance l'exercice dans cet univers", (tester) async {
      final (c, svc) = await open(tester, const UniverseScreen(theme: QuestTheme.aventures));
      c.read(questThemeProvider.notifier).select(QuestTheme.aventures);

      final mission = find.text('Suis la carte au trésor : repérage et déplacements');
      await tester.scrollUntilVisible(mission, 300);
      await tester.ensureVisible(mission);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(mission);
      await settle(tester);

      expect(svc.calls.single.$1, 'MA.GEO.07');
      expect(svc.calls.single.$2, ExerciseLevel.moyen);
      expect(svc.calls.single.$3, QuestTheme.aventures);
      expect(find.text('Les fractions du ballet'), findsOneWidget);
    });

    testWidgets('une mission déjà acquise est marquée comme réussie', (tester) async {
      DateTime d(int back) => DateTime.now().subtract(Duration(days: back));
      final progress = ProgressState(attempts: [
        for (var i = 1; i <= 3; i++)
          Attempt(competenceId: 'HI.T1.01', date: d(i), success: true),
      ]);
      await open(tester, const UniverseScreen(theme: QuestTheme.histoire), progress: progress);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets("depuis l'accueil : univers puis mission puis exercice", (tester) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({'gemini_api_key': 'TEST-KEY-123456'});
      final prefs = await SharedPreferences.getInstance();
      final svc = _FakeExercises();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        exerciseServiceProvider.overrideWith((ref) async => svc),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ReviskidsApp()),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Danse classique'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Danse classique'));
      await settle(tester);
      expect(find.text('Tes missions'), findsOneWidget);

      final mission = find.text('Le miroir de la salle de danse : la symétrie');
      await tester.scrollUntilVisible(mission, 300);
      await tester.ensureVisible(mission);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(mission);
      await settle(tester);

      expect(svc.calls.single.$1, 'MA.GEO.05');
      expect(svc.calls.single.$3, QuestTheme.danse);
    });
  });
}

void orauxTests() {
  group('notions qui se travaillent à l\'oral', () {
    test('lecture à voix haute et expression orale ne sont pas des exercices écrits', () {
      final c = Curriculum.fromJson(
        jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync()) as Map<String, dynamic>,
      );
      expect(c.competence('FR.LEC.01')!.ecrit, isFalse);
      expect(c.competence('FR.LEC.02')!.ecrit, isFalse);
      expect(c.competence('FR.ORA.01')!.ecrit, isFalse);
      expect(c.competence('EN.EOC.01')!.ecrit, isFalse);
      expect(c.competence('EN.CO.01')!.ecrit, isFalse);
      expect(c.competence('FR.LEC.03')!.ecrit, isTrue);
      expect(c.competence('MA.FRA.04')!.ecrit, isTrue);
    });

    test('les missions des univers sont toutes des exercices écrits', () {
      final c = Curriculum.fromJson(
        jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync()) as Map<String, dynamic>,
      );
      for (final info in universes.values) {
        for (final m in info.missions) {
          expect(c.competence(m.competenceId)!.ecrit, isTrue, reason: m.competenceId);
        }
      }
    });
  });
}
