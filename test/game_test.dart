import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revis_kids/core/curriculum.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/game/catalog.dart';
import 'package:revis_kids/game/game_state.dart';
import 'package:revis_kids/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Curriculum curriculum;

Future<ProviderContainer> containerWith({GameState? game, ProgressState? progress}) async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({
    if (game != null) 'game_v1': game.encode(),
    if (progress != null) 'progress_v1': progress.encode(),
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWith((ref) async => prefs),
    curriculumProvider.overrideWith((ref) async => curriculum),
  ]);
  addTearDown(c.dispose);
  return c;
}

Widget app(ProviderContainer c) =>
    UncontrolledProviderScope(container: c, child: const ReviskidsApp());

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    curriculum = Curriculum.fromJson(
      jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('niveaux', () {
    test('le niveau monte avec les XP', () {
      expect(levelFor(0), 1);
      expect(levelFor(79), 1);
      expect(levelFor(80), 2);
      expect(levelFor(240), 3);
      expect(xpForLevel(2), 80);
    });

    test('la progression vers le niveau suivant va de 0 à 1', () {
      expect(levelProgress(0), 0);
      expect(levelProgress(40), closeTo(0.5, 0.001));
      expect(levelProgress(80), 0);
    });
  });

  group('barème des récompenses', () {
    Reward r({int fails = 0, int capsules = 0, bool acquired = false, bool capped = false, String? m = 'mathematiques'}) =>
        computeReward(
          matiereId: m,
          fails: fails,
          capsules: capsules,
          becameAcquired: acquired,
          cappedToday: capped,
        );

    test('réussir seul du premier coup rapporte le plus', () {
      final x = r();
      expect((x.xp, x.stars, x.materialCount), (30, 3, 2));
      expect(x.materialId, 'pierre');
    });

    test('réussir après un indice rapporte moins', () {
      final x = r(fails: 1);
      expect((x.xp, x.stars, x.materialCount), (20, 2, 1));
    });

    test('réussir après la capsule rapporte encore, pour encourager à réviser', () {
      final x = r(fails: 0, capsules: 1);
      expect((x.xp, x.stars, x.materialCount), (15, 1, 1));
    });

    test('devenir « acquise » ajoute un gros bonus', () {
      final x = r(acquired: true);
      expect(x.xp, 80);
      expect(x.stars, 8);
      expect(x.becameAcquired, isTrue);
    });

    test('au-delà de 3 réussites par jour : plus de récompense', () {
      final x = r(capped: true);
      expect(x.isEmpty, isTrue);
      expect(x.cappedToday, isTrue);
    });

    test('un matériau par matière, sans matière pas de matériau', () {
      expect(materialForMatiere('francais').id, 'bois');
      expect(materialForMatiere('sciences').id, 'metal');
      expect(r(m: null).materialId, isNull);
      for (final b in buildings) {
        expect(materials.any((m) => m.matiereId == b.matiereId), isTrue, reason: b.id);
      }
    });
  });

  group('état du jeu', () {
    test("les gains sont ajoutés et le passage de niveau est signalé", () async {
      final c = await containerWith(game: const GameState(xp: 70));
      final reward = await c.read(gameProvider.notifier).applyReward(
            const Reward(xp: 30, stars: 3, materialId: 'bois', materialCount: 2),
          );
      final g = await c.read(gameProvider.future);
      expect(g.xp, 100);
      expect(g.stars, 3);
      expect(g.materialCount('bois'), 2);
      expect(reward.levelUpTo, 2);
    });

    test("tout est sauvegardé et relu", () async {
      final c = await containerWith();
      await c.read(gameProvider.notifier).applyReward(
            const Reward(xp: 10, stars: 4, materialId: 'pierre', materialCount: 1),
          );
      final prefs = await SharedPreferences.getInstance();
      final back = GameState.decode(prefs.getString('game_v1'));
      expect((back.xp, back.stars, back.materialCount('pierre')), (10, 4, 1));
      expect(GameState.decode('pas du json').xp, 0);
    });

    test('construire demande des matériaux', () async {
      final c = await containerWith(game: const GameState());
      final res = await c
          .read(gameProvider.notifier)
          .upgrade(buildingById('bibliotheque'), acquiredInMatiere: 0);
      expect(res, BuildResult.notEnoughMaterials);
    });

    test('construire retire les matériaux et monte le niveau', () async {
      final c = await containerWith(game: const GameState(materials: {'bois': 7}));
      final res = await c
          .read(gameProvider.notifier)
          .upgrade(buildingById('bibliotheque'), acquiredInMatiere: 0);
      final g = await c.read(gameProvider.future);
      expect(res, BuildResult.ok);
      expect(g.buildingLevel('bibliotheque'), 1);
      expect(g.materialCount('bois'), 2);
    });

    test('le niveau 2 exige de vraies notions acquises', () async {
      final c = await containerWith(
        game: const GameState(
          materials: {'bois': 50},
          buildingLevels: {'bibliotheque': 1},
        ),
      );
      final n = c.read(gameProvider.notifier);
      final b = buildingById('bibliotheque');
      expect(await n.upgrade(b, acquiredInMatiere: 0), BuildResult.needsMastery);
      expect(await n.upgrade(b, acquiredInMatiere: 1), BuildResult.ok);
      expect((await c.read(gameProvider.future)).buildingLevel('bibliotheque'), 2);
    });

    test('niveau maximum respecté', () async {
      final c = await containerWith(
        game: const GameState(
          materials: {'bois': 99},
          buildingLevels: {'bibliotheque': 3},
        ),
      );
      expect(
        await c.read(gameProvider.notifier).upgrade(buildingById('bibliotheque'), acquiredInMatiere: 9),
        BuildResult.maxLevel,
      );
    });
  });

  group('boutique', () {
    test('acheter coûte des étoiles', () async {
      final c = await containerWith(game: const GameState(stars: 20));
      final n = c.read(gameProvider.notifier);
      final robot = shopItemById('av_robot');
      expect(await n.buy(robot), BuyResult.ok);
      final g = await c.read(gameProvider.future);
      expect(g.stars, 5);
      expect(g.owns('av_robot'), isTrue);
      expect(await n.buy(robot), BuyResult.alreadyOwned);
    });

    test("pas assez d'étoiles : rien n'est acheté", () async {
      final c = await containerWith(game: const GameState(stars: 3));
      expect(await c.read(gameProvider.notifier).buy(shopItemById('av_fusee')), BuyResult.notEnoughStars);
      expect((await c.read(gameProvider.future)).stars, 3);
    });

    test('les avatars gratuits sont offerts, un avatar non acheté ne peut pas être choisi', () async {
      final c = await containerWith();
      final n = c.read(gameProvider.notifier);
      await n.selectAvatar('av_chat');
      expect((await c.read(gameProvider.future)).avatarId, 'av_chat');
      await n.selectAvatar('av_etoile');
      expect((await c.read(gameProvider.future)).avatarId, 'av_chat');
    });
  });

  group('écrans', () {
    testWidgets("l'accueil : mascotte, bouton Scanner, univers, étoiles et accès parent", (tester) async {
      final c = await containerWith(game: const GameState(stars: 12, xp: 100));
      await tester.pumpWidget(app(c));
      await settle(tester);

      expect(find.text("C'est l'heure de ta mission du jour !"), findsOneWidget);
      expect(find.text('Scanner mon devoir'), findsOneWidget);
      expect(find.text('Histoire de France'), findsOneWidget);
      expect(find.text('Danse classique'), findsOneWidget);
      expect(find.text('Aventures'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Niveau 2'), findsOneWidget);
      expect(find.byTooltip('Espace parent'), findsOneWidget);
      expect(find.text('Mon village'), findsOneWidget);
      expect(find.text('Boutique'), findsOneWidget);
    });

    testWidgets("le village : on construit un bâtiment avec des matériaux", (tester) async {
      final c = await containerWith(game: const GameState(materials: {'bois': 6}));
      await tester.pumpWidget(app(c));
      await settle(tester);

      await tester.ensureVisible(find.text('Mon village'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Mon village'));
      await settle(tester);

      expect(find.text('Bibliothèque'), findsOneWidget);
      final build = find.widgetWithText(FilledButton, 'Construire').first;
      await tester.ensureVisible(build);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(build);
      await settle(tester);

      expect((await c.read(gameProvider.future)).buildingLevel('bibliotheque'), 1);
      expect(find.textContaining('Tu as construit'), findsOneWidget);
    });

    testWidgets("le village : un bâtiment sans assez de matériaux ne se construit pas", (tester) async {
      final c = await containerWith();
      await tester.pumpWidget(app(c));
      await settle(tester);
      await tester.ensureVisible(find.text('Mon village'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Mon village'));
      await settle(tester);

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Construire').first);
      expect(btn.onPressed, isNull);
      expect(find.textContaining('Il te manque 5 Bois'), findsOneWidget);
    });

    testWidgets("la boutique : on achète un avatar avec ses étoiles", (tester) async {
      final c = await containerWith(game: const GameState(stars: 20));
      await tester.pumpWidget(app(c));
      await settle(tester);
      await tester.ensureVisible(find.text('Boutique'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Boutique'));
      await settle(tester);

      final robot = find.text('Robot');
      await tester.ensureVisible(robot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(robot);
      await settle(tester);

      final g = await c.read(gameProvider.future);
      expect(g.owns('av_robot'), isTrue);
      expect(g.stars, 5);
    });
  });
}
