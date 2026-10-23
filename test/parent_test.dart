import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/data/pin_repository.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime day(int d) => DateTime(2026, 10, d, 17);

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final ch in pin.split('')) {
    await tester.tap(find.widgetWithText(FilledButton, ch));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 200));
  // Laisse les chargements asynchrones (assets, préférences) se terminer :
  // pumpAndSettle seul ne les attend pas et un spinner tourne sans fin.
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<SharedPreferences> freshPrefs() async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({});
  return prefs = await SharedPreferences.getInstance();
}

late Curriculum curriculum;
late SharedPreferences prefs;

Future<void> openParentSpace(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => prefs),
      curriculumProvider.overrideWith((ref) async => curriculum),
    ],
    child: const ReviskidsApp(),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Espace parent'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('statut des compétences', () {
    test('non vue sans tentative', () {
      expect(const ProgressState().statusOf('FR.ORT.02'), CompetenceStatus.nonVue);
    });

    test('en cours dès la première tentative, même ratée', () {
      final s = ProgressState(attempts: [
        Attempt(competenceId: 'X', date: day(1), success: false),
      ]);
      expect(s.statusOf('X'), CompetenceStatus.enCours);
    });

    test('3 réussites le même jour ne suffisent pas', () {
      final s = ProgressState(attempts: [
        for (var i = 0; i < 3; i++)
          Attempt(competenceId: 'X', date: day(1).add(Duration(minutes: i)), success: true),
      ]);
      expect(s.statusOf('X'), CompetenceStatus.enCours);
    });

    test('3 réussites sur 2 jours = acquise', () {
      final s = ProgressState(attempts: [
        Attempt(competenceId: 'X', date: day(1), success: true),
        Attempt(competenceId: 'X', date: day(2), success: true),
        Attempt(competenceId: 'X', date: day(3), success: true),
      ]);
      expect(s.statusOf('X'), CompetenceStatus.acquise);
    });

    test("un échec récent fait repasser la compétence « en cours »", () {
      final s = ProgressState(attempts: [
        Attempt(competenceId: 'X', date: day(1), success: true),
        Attempt(competenceId: 'X', date: day(2), success: true),
        Attempt(competenceId: 'X', date: day(3), success: true),
        Attempt(competenceId: 'X', date: day(4), success: false),
      ]);
      expect(s.statusOf('X'), CompetenceStatus.enCours);
    });

    test("l'état se sauvegarde et se relit", () {
      final s = ProgressState(
        attempts: [Attempt(competenceId: 'X', date: day(1), success: true, capsuleRead: true)],
        scans: [ScanRecord(id: '1', date: day(1), themeLabel: 'Aventures')],
      );
      final back = ProgressState.decode(s.encode());
      expect(back.attempts.single.capsuleRead, isTrue);
      expect(back.scans.single.themeLabel, 'Aventures');
    });
  });

  group('code PIN', () {
    test("seule une empreinte est stockée, jamais le code", () async {
      final repo = PinRepository(await freshPrefs());
      expect(repo.hasPin, isFalse);
      await repo.setPin('1234');
      expect(repo.hasPin, isTrue);
      expect(repo.verify('1234'), isTrue);
      expect(repo.verify('4321'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => prefs.get(k).toString().contains('1234')), isFalse);
    });

    test('format : exactement 4 chiffres', () {
      expect(PinRepository.isValidFormat('1234'), isTrue);
      expect(PinRepository.isValidFormat('123'), isFalse);
      expect(PinRepository.isValidFormat('12a4'), isFalse);
    });
  });

  group('espace parent', () {
    testWidgets('premier usage : création du PIN puis tableau de bord', (tester) async {
      await freshPrefs();
      await openParentSpace(tester);

      expect(find.text('Créez votre code parent'), findsOneWidget);
      await typePin(tester, '2468');
      expect(find.text('Confirmez votre code'), findsOneWidget);
      await typePin(tester, '2468');

      expect(find.text('Compétences'), findsOneWidget);
      expect(find.text('Historique'), findsOneWidget);
      expect(find.text('Progression'), findsOneWidget);
    });

    testWidgets('PIN de confirmation différent : on recommence', (tester) async {
      await freshPrefs();
      await openParentSpace(tester);

      await typePin(tester, '1111');
      await typePin(tester, '2222');

      expect(find.text('Créez votre code parent'), findsOneWidget);
      expect(find.textContaining('différents'), findsOneWidget);
    });

    testWidgets('mauvais code refusé, bon code accepté', (tester) async {
      await PinRepository(await freshPrefs()).setPin('1357');
      await openParentSpace(tester);

      expect(find.text('Code parent'), findsOneWidget);
      await typePin(tester, '0000');
      expect(find.text('Code incorrect.'), findsOneWidget);
      expect(find.text('Historique'), findsNothing);

      await typePin(tester, '1357');
      expect(find.text('Historique'), findsOneWidget);
    });

    testWidgets("l'historique est vide au départ et le tableau de bord affiche 0 acquise",
        (tester) async {
      await PinRepository(await freshPrefs()).setPin('1357');
      await openParentSpace(tester);
      await typePin(tester, '1357');

      expect(find.textContaining('0 acquise'), findsWidgets);
      await tester.tap(find.text('Historique'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucun devoir scanné'), findsOneWidget);
    });
  });
}
