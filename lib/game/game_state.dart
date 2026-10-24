import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../demo/demo_mode.dart';
import 'catalog.dart';

/// Points d'expérience nécessaires pour atteindre le niveau [level] (niveau 1 = 0).
int xpForLevel(int level) => 40 * level * (level - 1);

int levelFor(int xp) {
  var level = 1;
  while (xpForLevel(level + 1) <= xp) {
    level++;
  }
  return level;
}

/// Part (0 à 1) du chemin parcouru entre le niveau courant et le suivant.
double levelProgress(int xp) {
  final l = levelFor(xp);
  final start = xpForLevel(l);
  final end = xpForLevel(l + 1);
  return ((xp - start) / (end - start)).clamp(0.0, 1.0);
}

/// Nombre de réussites par jour et par compétence qui rapportent encore des
/// récompenses : au-delà, on félicite mais on ne récompense plus (anti-farming).
const int kReussitesRecompenseesParJour = 3;

/// Ce que rapporte un défi réussi.
class Reward {
  const Reward({
    this.xp = 0,
    this.stars = 0,
    this.materialId,
    this.materialCount = 0,
    this.becameAcquired = false,
    this.cappedToday = false,
    this.levelUpTo,
  });

  final int xp;
  final int stars;
  final String? materialId;
  final int materialCount;
  final bool becameAcquired;
  final bool cappedToday;
  final int? levelUpTo;

  bool get isEmpty => xp == 0 && stars == 0 && materialCount == 0;
}

/// Barème d'un défi réussi. Plus l'enfant réussit seul, plus il gagne ;
/// lire la capsule puis réussir rapporte tout de même, pour encourager à réviser.
///
/// [fails] : échecs avant la réussite dans le tour courant (0 à 2).
/// [capsules] : capsules « Bon à savoir » lues pour ce défi.
Reward computeReward({
  required String? matiereId,
  required int fails,
  required int capsules,
  required bool becameAcquired,
  required bool cappedToday,
}) {
  if (cappedToday) return const Reward(cappedToday: true);

  var xp = 15;
  var stars = 1;
  var mats = 1;
  if (capsules == 0 && fails == 0) {
    xp = 30;
    stars = 3;
    mats = 2;
  } else if (capsules == 0) {
    xp = 20;
    stars = 2;
    mats = 1;
  }
  if (becameAcquired) {
    xp += 50;
    stars += 5;
  }
  return Reward(
    xp: xp,
    stars: stars,
    materialId: matiereId == null ? null : materialForMatiere(matiereId).id,
    materialCount: matiereId == null ? 0 : mats,
    becameAcquired: becameAcquired,
  );
}

/// Barème d'une dictée corrigée : moins il y a d'erreurs, plus on gagne,
/// mais une dictée avec beaucoup d'erreurs rapporte quand même un peu pour
/// encourager à la refaire.
Reward computeDicteeReward({required int errors}) {
  final (xp, stars, mats) = errors == 0
      ? (30, 3, 2)
      : errors <= 2
          ? (20, 2, 1)
          : (10, 1, 1);
  return Reward(
    xp: xp,
    stars: stars,
    materialId: materialForMatiere('francais').id,
    materialCount: mats,
  );
}

/// XP gagnés en comprenant une capsule (quiz réussi).
const int kXpCapsuleComprise = 5;

class GameState {
  const GameState({
    this.xp = 0,
    this.stars = 0,
    this.materials = const {},
    this.buildingLevels = const {},
    this.owned = const {},
    this.avatarId = defaultAvatarId,
    this.avatarColor = 0,
  });

  final int xp;
  final int stars;
  final Map<String, int> materials;
  final Map<String, int> buildingLevels;
  final Set<String> owned;
  final String avatarId;
  final int avatarColor;

  int get level => levelFor(xp);
  int materialCount(String id) => materials[id] ?? 0;
  int buildingLevel(String id) => buildingLevels[id] ?? 0;

  bool owns(String itemId) =>
      shopItemById(itemId).price == 0 || owned.contains(itemId);

  GameState copyWith({
    int? xp,
    int? stars,
    Map<String, int>? materials,
    Map<String, int>? buildingLevels,
    Set<String>? owned,
    String? avatarId,
    int? avatarColor,
  }) =>
      GameState(
        xp: xp ?? this.xp,
        stars: stars ?? this.stars,
        materials: materials ?? this.materials,
        buildingLevels: buildingLevels ?? this.buildingLevels,
        owned: owned ?? this.owned,
        avatarId: avatarId ?? this.avatarId,
        avatarColor: avatarColor ?? this.avatarColor,
      );

  String encode() => jsonEncode({
        'xp': xp,
        'stars': stars,
        'materials': materials,
        'buildings': buildingLevels,
        'owned': owned.toList(),
        'avatar': avatarId,
        'color': avatarColor,
      });

  static GameState decode(String? raw) {
    if (raw == null) return const GameState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final colorIndex = (j['color'] as int?) ?? 0;
      return GameState(
        xp: (j['xp'] as int?) ?? 0,
        stars: (j['stars'] as int?) ?? 0,
        materials: Map<String, int>.from((j['materials'] as Map?) ?? {}),
        buildingLevels: Map<String, int>.from((j['buildings'] as Map?) ?? {}),
        owned: Set<String>.from((j['owned'] as List?) ?? []),
        avatarId: (j['avatar'] as String?) ?? defaultAvatarId,
        avatarColor: colorIndex.clamp(0, avatarColors.length - 1),
      );
    } catch (_) {
      return const GameState();
    }
  }
}

enum BuildResult { ok, notEnoughMaterials, needsMastery, maxLevel }

enum BuyResult { ok, notEnoughStars, alreadyOwned }

/// Résultat de la tentative d'amélioration d'un bâtiment.
BuildResult checkUpgrade({
  required GameState game,
  required Building building,
  required int acquiredInMatiere,
}) {
  final current = game.buildingLevel(building.id);
  if (current >= kBuildingMaxLevel) return BuildResult.maxLevel;
  if (acquiredInMatiere < kBuildingMastery[current]) return BuildResult.needsMastery;
  if (game.materialCount(building.material.id) < kBuildingCosts[current]) {
    return BuildResult.notEnoughMaterials;
  }
  return BuildResult.ok;
}

const _gameKey = 'game_v1';
const demoGameKey = 'demo_game_v1';

class GameNotifier extends AsyncNotifier<GameState> {
  @override
  Future<GameState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final demo = await ref.watch(demoModeProvider.future);
    return GameState.decode(prefs.getString(demo ? demoGameKey : _gameKey));
  }

  Future<GameState> _current() async => state.value ?? await future;

  Future<void> _save(GameState next) async {
    state = AsyncData(next);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final demo = await ref.read(demoModeProvider.future);
    await prefs.setString(demo ? demoGameKey : _gameKey, next.encode());
  }

  /// Ajoute les gains d'un défi réussi et renvoie la récompense finale
  /// (avec le passage de niveau éventuel).
  Future<Reward> applyReward(Reward reward) async {
    if (reward.isEmpty) return reward;
    final g = await _current();
    final before = g.level;
    final mats = {...g.materials};
    if (reward.materialId != null) {
      mats[reward.materialId!] = (mats[reward.materialId!] ?? 0) + reward.materialCount;
    }
    final next = g.copyWith(
      xp: g.xp + reward.xp,
      stars: g.stars + reward.stars,
      materials: mats,
    );
    await _save(next);
    return Reward(
      xp: reward.xp,
      stars: reward.stars,
      materialId: reward.materialId,
      materialCount: reward.materialCount,
      becameAcquired: reward.becameAcquired,
      cappedToday: reward.cappedToday,
      levelUpTo: next.level > before ? next.level : null,
    );
  }

  Future<void> addXp(int amount) async {
    final g = await _current();
    await _save(g.copyWith(xp: g.xp + max(0, amount)));
  }

  Future<BuildResult> upgrade(Building building, {required int acquiredInMatiere}) async {
    final g = await _current();
    final res = checkUpgrade(game: g, building: building, acquiredInMatiere: acquiredInMatiere);
    if (res != BuildResult.ok) return res;
    final level = g.buildingLevel(building.id);
    final mats = {...g.materials};
    final matId = building.material.id;
    mats[matId] = (mats[matId] ?? 0) - kBuildingCosts[level];
    await _save(g.copyWith(
      materials: mats,
      buildingLevels: {...g.buildingLevels, building.id: level + 1},
    ));
    return BuildResult.ok;
  }

  Future<BuyResult> buy(ShopItem item) async {
    final g = await _current();
    if (g.owns(item.id)) return BuyResult.alreadyOwned;
    if (g.stars < item.price) return BuyResult.notEnoughStars;
    await _save(g.copyWith(stars: g.stars - item.price, owned: {...g.owned, item.id}));
    return BuyResult.ok;
  }

  Future<void> selectAvatar(String id) async {
    final g = await _current();
    if (!g.owns(id)) return;
    await _save(g.copyWith(avatarId: id));
  }

  Future<void> selectAvatarColor(int index) async {
    final g = await _current();
    await _save(g.copyWith(avatarColor: index.clamp(0, avatarColors.length - 1)));
  }
}

final gameProvider =
    AsyncNotifierProvider<GameNotifier, GameState>(GameNotifier.new);
