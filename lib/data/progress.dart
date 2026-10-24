import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../demo/demo_mode.dart';
import 'prefs.dart';

export 'prefs.dart';

enum CompetenceStatus { nonVue, enCours, acquise }

/// Une tentative de l'élève sur un exercice lié à une compétence.
class Attempt {
  const Attempt({
    required this.competenceId,
    required this.date,
    required this.success,
    this.capsuleRead = false,
  });

  final String competenceId;
  final DateTime date;
  final bool success;

  /// L'élève a dû lire la capsule « Bon à savoir » avant de réussir.
  final bool capsuleRead;

  Map<String, dynamic> toJson() => {
        'c': competenceId,
        'd': date.toIso8601String(),
        's': success,
        'k': capsuleRead,
      };

  factory Attempt.fromJson(Map<String, dynamic> j) => Attempt(
        competenceId: j['c'] as String,
        date: DateTime.parse(j['d'] as String),
        success: j['s'] as bool,
        capsuleRead: (j['k'] as bool?) ?? false,
      );
}

const String kindDevoir = 'devoir';
const String kindDictee = 'dictee';
const String kindExercice = 'exercice';

/// Un devoir scanné. La photo n'est jamais conservée sur l'appareil.
class ScanRecord {
  const ScanRecord({
    required this.id,
    required this.date,
    required this.themeLabel,
    this.matiereId,
    this.competenceId,
    this.note,
    this.kind = kindDevoir,
    this.errors = const {},
  });

  final String id;
  final DateTime date;
  final String themeLabel;
  final String? matiereId;
  final String? competenceId;

  /// Précision donnée avant le scan (« exercice 3 page 45 »).
  final String? note;

  /// [kindDevoir], [kindDictee] ou [kindExercice].
  final String kind;

  /// Pour une dictée : nombre d'erreurs par catégorie (accord, grammaire, lexique, autre).
  final Map<String, int> errors;

  Map<String, dynamic> toJson() => {
        'i': id,
        'd': date.toIso8601String(),
        't': themeLabel,
        'm': matiereId,
        'c': competenceId,
        'n': note,
        'y': kind,
        'e': errors,
      };

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
        id: j['i'] as String,
        date: DateTime.parse(j['d'] as String),
        themeLabel: j['t'] as String,
        matiereId: j['m'] as String?,
        competenceId: j['c'] as String?,
        note: j['n'] as String?,
        kind: (j['y'] as String?) ?? kindDevoir,
        errors: Map<String, int>.from((j['e'] as Map?) ?? const {}),
      );
}

/// Seuils de validation d'une compétence (voir [ProgressState.statusOf]).
const int kReussitesPourAcquise = 3;
const int kJoursDistinctsPourAcquise = 2;

class ProgressState {
  const ProgressState({this.attempts = const [], this.scans = const []});

  final List<Attempt> attempts;
  final List<ScanRecord> scans;

  List<Attempt> attemptsFor(String competenceId) =>
      attempts.where((a) => a.competenceId == competenceId).toList();

  /// « Acquise » : au moins 3 réussites, sur au moins 2 jours différents
  /// (pour retenir et pas seulement réussir une fois), et la dernière
  /// tentative est réussie. « En cours » dès la première tentative.
  CompetenceStatus statusOf(String competenceId) {
    final list = attemptsFor(competenceId);
    if (list.isEmpty) return CompetenceStatus.nonVue;
    list.sort((a, b) => a.date.compareTo(b.date));
    final wins = list.where((a) => a.success).toList();
    final days = {
      for (final w in wins) DateTime(w.date.year, w.date.month, w.date.day),
    };
    if (wins.length >= kReussitesPourAcquise &&
        days.length >= kJoursDistinctsPourAcquise &&
        list.last.success) {
      return CompetenceStatus.acquise;
    }
    return CompetenceStatus.enCours;
  }

  ProgressState copyWith({List<Attempt>? attempts, List<ScanRecord>? scans}) =>
      ProgressState(
        attempts: attempts ?? this.attempts,
        scans: scans ?? this.scans,
      );

  String encode() => jsonEncode({
        'attempts': [for (final a in attempts) a.toJson()],
        'scans': [for (final s in scans) s.toJson()],
      });

  static ProgressState decode(String? raw) {
    if (raw == null) return const ProgressState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ProgressState(
        attempts: [
          for (final a in j['attempts'] as List)
            Attempt.fromJson(a as Map<String, dynamic>),
        ],
        scans: [
          for (final s in j['scans'] as List)
            ScanRecord.fromJson(s as Map<String, dynamic>),
        ],
      );
    } catch (_) {
      return const ProgressState();
    }
  }
}


const _progressKey = 'progress_v1';

/// Les données du mode démo sont rangées à part : elles ne se mélangent jamais
/// avec le vrai suivi de l'enfant, et disparaissent quand on les efface.
const demoProgressKey = 'demo_progress_v1';

class ProgressNotifier extends AsyncNotifier<ProgressState> {
  @override
  Future<ProgressState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final demo = await ref.watch(demoModeProvider.future);
    return ProgressState.decode(prefs.getString(demo ? demoProgressKey : _progressKey));
  }

  Future<void> _save(ProgressState next) async {
    state = AsyncData(next);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final demo = await ref.read(demoModeProvider.future);
    await prefs.setString(demo ? demoProgressKey : _progressKey, next.encode());
  }

  Future<ProgressState> _current() async =>
      state.value ?? await future;

  Future<void> addScan(ScanRecord scan) async {
    final s = await _current();
    await _save(s.copyWith(scans: [...s.scans, scan]));
  }

  Future<void> recordAttempt(Attempt attempt) async {
    final s = await _current();
    await _save(s.copyWith(attempts: [...s.attempts, attempt]));
  }

  Future<void> replaceAll(ProgressState next) => _save(next);

  Future<void> clear() => _save(const ProgressState());
}

final progressProvider =
    AsyncNotifierProvider<ProgressNotifier, ProgressState>(ProgressNotifier.new);
