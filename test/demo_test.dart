import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revis_kids/ai/exercise.dart';
import 'package:revis_kids/ai/quest.dart';
import 'package:revis_kids/ai/tutor.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/core/quest_theme.dart';
import 'package:revis_kids/core/universe_missions.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/demo/demo_content.dart';
import 'package:revis_kids/demo/demo_mode.dart';
import 'package:revis_kids/dictee/dictee_text.dart';
import 'package:revis_kids/dictee/speech.dart';
import 'package:revis_kids/features/scan/photo_capture_view.dart';
import 'package:revis_kids/game/game_state.dart';
import 'package:revis_kids/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Curriculum curriculum;

final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

DemoAi ai({DemoVerdict v = DemoVerdict.incorrect, DemoDictee d = DemoDictee.errors}) =>
    DemoAi(verdict: () => v, dictee: () => d);

/// Fait défiler la page jusqu'au bouton, puis le touche (comme un enfant).
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f);
}

class _FakeSpeech implements SpeechService {
  @override
  Future<bool> init() async => true;
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(SpeechRate rate) async {}
}

void main() {
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('contenu de démo', () {
    test('toutes les missions des univers ont un vrai exercice rédigé', () {
      for (final info in universes.values) {
        for (final m in info.missions) {
          expect(demoExercises.containsKey(m.competenceId), isTrue, reason: m.competenceId);
        }
      }
    });

    test('tous les exercices rédigés visent une notion qui existe', () {
      for (final id in demoExercises.keys) {
        expect(curriculum.competence(id), isNotNull, reason: id);
      }
    });

    test('les exercices rédigés ne donnent pas leur propre réponse', () {
      for (final e in demoExercises.entries) {
        expect(e.value.defi.toLowerCase(), isNot(contains('réponse :')), reason: e.key);
        expect(e.value.defi, isNotEmpty);
      }
    });
  });

  group('exercices simulés', () {
    test('une notion, un exercice, pour chacune des 92 notions et chaque niveau', () async {
      final demo = ai();
      for (final c in curriculum.competences) {
        for (final level in ExerciseLevel.values) {
          final q = await demo.generateExercise(
            competence: c,
            theme: QuestTheme.aventures,
            level: level,
          );
          expect(q.competenceId, c.id);
          expect(q.matiereId, c.matiereId);
          expect(q.defi, isNotEmpty);
          expect(q.consigneEcriture, contains('cahier'));
          expect(q.needsConfirmation, isFalse);
        }
      }
    });

    test('les trois niveaux donnent des exercices différents', () async {
      final c = curriculum.competence('MA.FRA.04')!;
      Future<String> defi(ExerciseLevel l) async =>
          (await ai().generateExercise(competence: c, theme: QuestTheme.danse, level: l)).defi;
      final all = {await defi(ExerciseLevel.facile), await defi(ExerciseLevel.moyen), await defi(ExerciseLevel.defi)};
      expect(all.length, 3);
    });

    test('une notion sans exercice rédigé reçoit un exercice générique signalé', () async {
      final c = curriculum.competence('SC.MAT.03')!;
      expect(demoExercises.containsKey(c.id), isFalse);
      final q = await ai().generateExercise(competence: c, theme: QuestTheme.histoire, level: ExerciseLevel.moyen);
      expect(q.defi, contains('démonstration'));
    });
  });

  group('recherche simulée', () {
    Future<QuestResult> search(String? note, {Uint8List? image}) => ai().createQuest(
          image: image,
          theme: QuestTheme.aventures,
          curriculum: curriculum,
          note: note,
        );

    test('un mot-clé reconnu donne la bonne notion, sans doute', () async {
      final q = (await search('exercice 3 page 45, les fractions')).quest!;
      expect(q.competenceId, 'MA.FRA.03');
      expect(q.needsConfirmation, isFalse);
      expect((await search('la symétrie axiale')).quest!.competenceId, 'MA.GEO.05');
      expect((await search('le château fort')).quest!.competenceId, 'HI.T1.01');
    });

    test('sans mot-clé ou avec une simple photo : la confirmation est démontrée', () async {
      final q = (await search('truc bizarre')).quest!;
      expect(q.needsConfirmation, isTrue);
      expect(q.questionConfirmation, contains('Mode démo'));
      expect((await search(null, image: png)).quest!.needsConfirmation, isTrue);
    });
  });

  group('tuteur simulé', () {
    const quest = Quest(
      enonceTranscrit: 'x',
      titre: 'x',
      scenario: 'x',
      defi: 'x',
      consigneEcriture: 'x',
      confiance: 1,
    );
    Competence comp() => curriculum.competence('MA.FRA.03')!;

    Future<Verification> verify(DemoVerdict v, [int attempt = 1]) => ai(v: v).verifyAnswer(
          image: png,
          mimeType: 'image/png',
          quest: quest,
          competence: comp(),
          theme: QuestTheme.aventures,
          attemptNumber: attempt,
        );

    test('bonne réponse', () async {
      final v = await verify(DemoVerdict.correct);
      expect(v.correct, isTrue);
      expect(v.message, contains('simulée'));
    });

    test('mauvaise réponse : indices progressifs, jamais de réponse', () async {
      final v1 = await verify(DemoVerdict.incorrect, 1);
      final v2 = await verify(DemoVerdict.incorrect, 2);
      expect(v1.correct, isFalse);
      expect(v1.message, isNot(v2.message));
      expect(v2.message, contains(comp().titre));
      expect(v1.reponseAttendue, isNull);
    });

    test('écriture illisible : la confirmation est demandée', () async {
      final v = await verify(DemoVerdict.unreadable);
      expect(v.lectureIncertaine, isTrue);
      expect(v.questionConfirmation, contains('Mode démo'));
    });

    test('capsule valable pour chacune des 92 notions', () async {
      final demo = ai();
      for (final c in curriculum.competences) {
        final capsule = await demo.createCapsule(quest: quest, competence: c, theme: QuestTheme.danse);
        expect(capsule.quiz, hasLength(2), reason: c.id);
        for (final q in capsule.quiz) {
          expect(q.choix.length, 3, reason: c.id);
          expect(q.choix.toSet().length, 3, reason: '${c.id} : choix identiques');
          expect(q.bonneReponse, inInclusiveRange(0, 2), reason: c.id);
        }
        expect(capsule.quiz[0].choix[capsule.quiz[0].bonneReponse], c.titre);
        expect(capsule.quiz[1].choix[capsule.quiz[1].bonneReponse], c.objectifs.first);
        expect(capsule.lecon, contains(c.objectifs.first));
      }
    });
  });

  group('dictée simulée', () {
    test('une dictée par univers, assez longue pour être découpée', () async {
      for (final theme in QuestTheme.values) {
        final t = await ai().generateText(theme: theme, curriculum: curriculum);
        final words = t.texte.split(RegExp(r'\s+')).length;
        expect(words, inInclusiveRange(35, 70), reason: theme.name);
        expect(splitDictee(t.texte).length, greaterThanOrEqualTo(3), reason: theme.name);
      }
    });

    Future<DicteeCorrection> correct(String source, DemoDictee d) => ai(d: d).correct(
          image: png,
          mimeType: 'image/png',
          texteSource: source,
          curriculum: curriculum,
        );

    test('sans faute', () async {
      final src = demoDictees[QuestTheme.danse]!.$2;
      final c = await correct(src, DemoDictee.perfect);
      expect(c.nbErreurs, 0);
      expect(c.competences.every((x) => x.reussie), isTrue);
    });

    test('avec erreurs : trois catégories, mots tirés du texte, notions valides', () async {
      for (final theme in QuestTheme.values) {
        final src = demoDictees[theme]!.$2;
        final c = await correct(src, DemoDictee.errors);
        expect(c.nbErreurs, 3, reason: theme.name);
        expect(c.parCategorie.keys.toSet(),
            {ErrorCategory.accord, ErrorCategory.lexique, ErrorCategory.grammaire});
        for (final e in c.erreurs) {
          expect(src, contains(e.motAttendu), reason: e.motAttendu);
          expect(e.motEcrit, isNot(e.motAttendu));
          expect(e.explication, isNotEmpty);
          if (e.competenceId != null) {
            expect(curriculum.competence(e.competenceId!), isNotNull);
          }
        }
      }
    });

    test('écriture illisible : confirmation demandée avant correction', () async {
      final c = await correct(demoDictees[QuestTheme.histoire]!.$2, DemoDictee.unreadable);
      expect(c.lectureIncertaine, isTrue);
      expect(c.questionConfirmation, contains('Mode démo'));
    });
  });

  group('parcours de démo dans l\'application', () {
    late SharedPreferences prefs;

    Future<ProviderContainer> openApp(
      WidgetTester tester, {
      bool demo = true,
      bool key = false,
    }) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        if (demo) 'demo_mode': true,
        if (key) 'gemini_api_key': 'TEST-KEY-123456',
      });
      prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
        speechServiceProvider.overrideWithValue(_FakeSpeech()),
        photoPickerProvider.overrideWithValue(
          ({required bool camera}) async => (bytes: png, mimeType: 'image/png'),
        ),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ReviskidsApp()),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return container;
    }

    Future<void> settle(WidgetTester tester, [int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('démo active : pastille, bandeau, plus de message « pas prête »', (tester) async {
      await openApp(tester);
      expect(find.text('DÉMO'), findsOneWidget);
      expect(find.textContaining("Mode démo : l'IA est simulée"), findsOneWidget);
      expect(find.textContaining("n'est pas encore prête"), findsNothing);
    });

    testWidgets('sans clé ni démo : la démo est proposée, et elle s\'active d\'un clic', (tester) async {
      final c = await openApp(tester, demo: false);
      expect(find.textContaining("n'est pas encore prête"), findsOneWidget);
      expect(find.text('DÉMO'), findsNothing);

      await tester.tap(find.text('Essayer le mode démo (sans clé)'));
      await settle(tester, 4);

      expect(await c.read(demoModeProvider.future), isTrue);
      expect(prefs.getBool('demo_mode'), isTrue);
      expect(find.text('DÉMO'), findsOneWidget);
      expect(find.textContaining("n'est pas encore prête"), findsNothing);
    });

    testWidgets('on peut quitter la démo depuis le bandeau', (tester) async {
      final c = await openApp(tester);
      await tester.tap(find.text('Quitter'));
      await settle(tester, 4);
      expect(await c.read(demoModeProvider.future), isFalse);
      expect(find.text('DÉMO'), findsNothing);
    });

    testWidgets('parcours complet : recherche, trois échecs, capsule, quiz, réussite', (tester) async {
      final c = await openApp(tester);

      // 1. Recherche.
      await tester.enterText(find.byType(TextField), 'exercice 3 page 45, les fractions');
      await tester.pump();
      await tester.tap(find.text('Lancer la recherche'));
      await settle(tester);
      final fractions = curriculum.competence('MA.FRA.03')!;
      expect(find.text(fractions.titre), findsOneWidget);
      expect(find.textContaining('3/8 + 2/8'), findsOneWidget);

      // 2. Trois mauvaises réponses (scénario par défaut), avec indices.
      await tester.tap(find.text("J'ai écrit ma réponse : je la montre"));
      await settle(tester, 4);
      expect(find.text("Démo : l'IA répondra…"), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tapVisible(tester, find.text('Choisir une photo'));
        await tester.pump(const Duration(milliseconds: 100));
        await tapVisible(tester, find.text('Vérifier ma réponse'));
        await settle(tester);
        expect(find.textContaining('Pas encore'), findsOneWidget);
        await tapVisible(tester, find.text('Je réessaie'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tapVisible(tester, find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 100));
      await tapVisible(tester, find.text('Vérifier ma réponse'));
      await settle(tester);

      // 3. Capsule : lecture imposée, puis quiz.
      expect(find.textContaining('Bon à savoir'), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      await tester.tap(find.textContaining("J'ai lu"));
      await settle(tester, 3);
      await tester.tap(find.text(fractions.titre));
      await settle(tester, 3);
      await tester.tap(find.text(fractions.objectifs.first));
      await settle(tester, 3);
      expect(find.textContaining('Retente maintenant le même défi'), findsOneWidget);

      // 4. Bonne réponse, au choix du testeur.
      await tapVisible(tester, find.text('Bonne réponse'));
      await tester.pump(const Duration(milliseconds: 100));
      await tapVisible(tester, find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 100));
      await tapVisible(tester, find.text('Vérifier ma réponse'));
      await settle(tester);
      expect(find.text('Défi réussi !'), findsOneWidget);

      // 5. Les données vont dans la démo, jamais dans le vrai suivi.
      final progress = await c.read(progressProvider.future);
      expect(progress.attempts.map((a) => a.success), [false, false, false, true]);
      expect(prefs.getString('demo_progress_v1'), isNotNull);
      expect(prefs.getString('demo_game_v1'), isNotNull);
      expect(prefs.getString('progress_v1'), isNull);
      expect(prefs.getString('game_v1'), isNull);
      expect((await c.read(gameProvider.future)).xp, greaterThan(0));
    });

    testWidgets('en démo, on peut continuer sans photo', (tester) async {
      await openApp(tester);
      await tester.enterText(find.byType(TextField), 'les fractions');
      await tester.pump();
      await tester.tap(find.text('Lancer la recherche'));
      await settle(tester);
      await tester.tap(find.text("J'ai écrit ma réponse : je la montre"));
      await settle(tester, 4);

      await tapVisible(tester, find.text('Continuer sans photo (démo)'));
      await settle(tester);
      expect(find.textContaining('Pas encore'), findsOneWidget);
    });

    testWidgets("hors démo, ce bouton n'existe pas", (tester) async {
      await openApp(tester, demo: false, key: true);
      // Le bouton ne doit jamais apparaître sur l'écran de photo hors démo.
      expect(find.text('Continuer sans photo (démo)'), findsNothing);
      expect(find.text('DÉMO'), findsNothing);
    });

    testWidgets("la sortie de la démo retrouve le vrai suivi, resté intact", (tester) async {
      final real = ProgressState(attempts: [
        Attempt(competenceId: 'FR.ORT.02', date: DateTime(2026, 10, 1), success: true),
      ]);
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        'demo_mode': true,
        'progress_v1': real.encode(),
      });
      prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        curriculumProvider.overrideWith((ref) async => curriculum),
      ]);
      addTearDown(c.dispose);

      expect((await c.read(progressProvider.future)).attempts, isEmpty);
      await c.read(progressProvider.notifier).recordAttempt(
            Attempt(competenceId: 'MA.FRA.03', date: DateTime(2026, 10, 2), success: true),
          );
      await c.read(demoModeProvider.notifier).set(false);
      final back = await c.read(progressProvider.future);
      expect(back.attempts.single.competenceId, 'FR.ORT.02');
    });

    testWidgets('dictée en démo : surprise, lecture, correction sans faute', (tester) async {
      final c = await openApp(tester);
      await tester.ensureVisible(find.text('Dictée magique'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Dictée magique'));
      await settle(tester, 4);

      await tester.tap(find.text('Dictée surprise'));
      await settle(tester);
      expect(find.text('Ta dictée est prête !'), findsOneWidget);
      await tester.tap(find.text('Commencer la dictée'));
      await settle(tester);
      await tester.tap(find.text("J'ai écouté : on commence"));
      await settle(tester);
      // On avance morceau par morceau jusqu'à l'écran de la photo.
      for (var i = 0; i < 14; i++) {
        if (find.text("Démo : l'IA trouvera…").evaluate().isNotEmpty) break;
        final next = find.textContaining("J'ai").first;
        await tester.ensureVisible(next);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(next);
        await settle(tester, 3);
      }
      expect(find.text("Démo : l'IA trouvera…"), findsOneWidget);

      await tapVisible(tester, find.text('Sans faute'));
      await tester.pump(const Duration(milliseconds: 100));
      await tapVisible(tester, find.text('Choisir une photo'));
      await tester.pump(const Duration(milliseconds: 100));
      await tapVisible(tester, find.text('Corriger ma dictée'));
      await settle(tester);

      expect(find.text('Dictée sans faute, bravo !'), findsOneWidget);
      expect((await c.read(progressProvider.future)).scans.single.kind, kindDictee);
      expect(prefs.getString('progress_v1'), isNull);
    });
  });
}
