import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/curriculum.dart';
import '../../data/progress.dart';
import '../../dictee/dictee_text.dart';
import '../../game/catalog.dart';
import '../../game/game_state.dart';
import 'ai_settings_screen.dart';
import 'sample_data.dart';

const _mois = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String formatDate(DateTime d) => '${d.day} ${_mois[d.month - 1]} ${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)} à ${d.hour.toString().padLeft(2, '0')}h'
    '${d.minute.toString().padLeft(2, '0')}';

class ParentDashboard extends ConsumerWidget {
  const ParentDashboard({super.key, required this.onLock});

  final VoidCallback onLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final curriculum = ref.watch(curriculumProvider);
    final progress = ref.watch(progressProvider);
    final game = ref.watch(gameProvider).value ?? const GameState();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Espace parent'),
          backgroundColor: Colors.transparent,
          actions: [
            if (kDebugMode)
              IconButton(
                tooltip: "Charger des données d'exemple (mode développeur)",
                icon: const Icon(Icons.science_outlined),
                onPressed: () => loadSampleData(ref),
              ),
            IconButton(
              tooltip: 'Moteur IA',
              icon: const Icon(Icons.key_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Verrouiller',
              icon: const Icon(Icons.lock_rounded),
              onPressed: onLock,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.verified_rounded), text: 'Compétences'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Historique'),
              Tab(icon: Icon(Icons.trending_up_rounded), text: 'Progression'),
            ],
          ),
        ),
        body: switch ((curriculum, progress)) {
          (AsyncData(value: final c), AsyncData(value: final p)) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: TabBarView(
                  children: [
                    CompetencesTab(curriculum: c, progress: p),
                    HistoryTab(curriculum: c, progress: p),
                    ProgressTab(curriculum: c, progress: p, game: game),
                  ],
                ),
              ),
            ),
          (AsyncError(), _) || (_, AsyncError()) => const Center(
              child: Text('Impossible de charger les données.'),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

Color statusColor(CompetenceStatus s) => switch (s) {
      CompetenceStatus.acquise => const Color(0xFF2E7D32),
      CompetenceStatus.enCours => const Color(0xFFEF8F00),
      CompetenceStatus.nonVue => const Color(0xFF9E9E9E),
    };

String statusLabel(CompetenceStatus s) => switch (s) {
      CompetenceStatus.acquise => 'Acquise',
      CompetenceStatus.enCours => 'En cours',
      CompetenceStatus.nonVue => 'Pas encore vue',
    };

IconData statusIcon(CompetenceStatus s) => switch (s) {
      CompetenceStatus.acquise => Icons.check_circle_rounded,
      CompetenceStatus.enCours => Icons.timelapse_rounded,
      CompetenceStatus.nonVue => Icons.radio_button_unchecked_rounded,
    };

class CompetencesTab extends StatelessWidget {
  const CompetencesTab({super.key, required this.curriculum, required this.progress});

  final Curriculum curriculum;
  final ProgressState progress;

  @override
  Widget build(BuildContext context) {
    final all = curriculum.competences;
    final counts = {
      for (final s in CompetenceStatus.values)
        s: all.where((c) => progress.statusOf(c.id) == s).length,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in CompetenceStatus.values.reversed)
              _CountChip(status: s, count: counts[s]!),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Une compétence est « acquise » après $kReussitesPourAcquise '
            'réussites sur au moins $kJoursDistinctsPourAcquise jours '
            'différents, la dernière tentative étant réussie.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final m in curriculum.matieres)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(m.nom,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${m.competences.where((c) => progress.statusOf(c.id) == CompetenceStatus.acquise).length}'
                ' / ${m.competences.length} acquises',
              ),
              children: [
                for (final d in m.domaines) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(d.nom,
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                  ),
                  for (final c in d.competences)
                    _CompetenceRow(competence: c, progress: progress),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.status, required this.count});

  final CompetenceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Chip(
      avatar: Icon(statusIcon(status), color: color, size: 20),
      label: Text('$count ${statusLabel(status).toLowerCase()}'),
      side: BorderSide(color: color),
    );
  }
}

class _CompetenceRow extends StatelessWidget {
  const _CompetenceRow({required this.competence, required this.progress});

  final Competence competence;
  final ProgressState progress;

  @override
  Widget build(BuildContext context) {
    final status = progress.statusOf(competence.id);
    final attempts = progress.attemptsFor(competence.id);
    final wins = attempts.where((a) => a.success).length;
    return ListTile(
      dense: true,
      leading: Icon(statusIcon(status), color: statusColor(status)),
      title: Text(competence.titre),
      subtitle: Text(
        attempts.isEmpty
            ? statusLabel(status)
            : '${statusLabel(status)} · $wins réussite(s) sur ${attempts.length} essai(s)',
      ),
    );
  }
}

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key, required this.curriculum, required this.progress});

  final Curriculum curriculum;
  final ProgressState progress;

  @override
  Widget build(BuildContext context) {
    final scans = [...progress.scans]..sort((a, b) => b.date.compareTo(a.date));
    if (scans.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aucun devoir scanné pour le moment.\n'
            'Ils apparaîtront ici dès que votre enfant en aura scanné un.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: scans.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = scans[i];
        final comp = s.competenceId == null ? null : curriculum.competence(s.competenceId!);
        final matiere = s.matiereId == null ? null : curriculum.matiere(s.matiereId!);
        final isDictee = s.kind == kindDictee;
        final isExercice = s.kind == kindExercice;
        return Card(
          child: ListTile(
            leading: Icon(isDictee ? Icons.record_voice_over_rounded : Icons.description_outlined),
            title: Text(isDictee
                ? 'Dictée : ${s.note ?? 'sans titre'} — ${_dicteeSummary(s.errors)}'
                : isExercice
                    ? 'Exercice : ${comp?.titre ?? 'notion du programme'}'
                    : (comp?.titre ?? 'Compétence à identifier')),
            subtitle: Text(
              '${formatDateTime(s.date)} · ${matiere?.nom ?? 'Matière à identifier'}'
              ' · Univers : ${s.themeLabel}'
              '${(isDictee || isExercice || s.note == null) ? '' : '\nPrécision : ${s.note}'}',
            ),
          ),
        );
      },
    );
  }
}

class ProgressTab extends StatelessWidget {
  const ProgressTab({
    super.key,
    required this.curriculum,
    required this.progress,
    this.game = const GameState(),
  });

  final Curriculum curriculum;
  final ProgressState progress;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final all = curriculum.competences;
    final acquired = all
        .where((c) => progress.statusOf(c.id) == CompetenceStatus.acquise)
        .length;
    final ratio = all.isEmpty ? 0.0 : acquired / all.length;
    final attempts = progress.attempts;
    final wins = attempts.where((a) => a.success).length;
    final capsules = attempts.where((a) => a.capsuleRead).length;

    final today = DateTime.now();
    final days = [
      for (var i = 13; i >= 0; i--)
        DateTime(today.year, today.month, today.day).subtract(Duration(days: i)),
    ];
    final perDay = [
      for (final d in days)
        attempts
            .where((a) =>
                a.date.year == d.year && a.date.month == d.month && a.date.day == d.day)
            .length,
    ];
    final maxDay = perDay.fold<int>(1, (m, v) => v > m ? v : m);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 10,
                        backgroundColor: scheme.primary.withValues(alpha: 0.15),
                      ),
                      Center(
                        child: Text(
                          '${(ratio * 100).round()} %',
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Programme CM1',
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('$acquired compétences acquises sur ${all.length}'),
                      const SizedBox(height: 8),
                      Text('${progress.scans.length} devoir(s) scanné(s)'),
                      Text(attempts.isEmpty
                          ? 'Aucun exercice réalisé'
                          : '$wins réussite(s) sur ${attempts.length} essai(s) '
                              '(${(wins * 100 / attempts.length).round()} %)'),
                      Text('$capsules capsule(s) « Bon à savoir » lue(s)'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aventure de votre enfant',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Niveau ${game.level} · ${game.xp} XP · ${game.stars} étoile(s)'),
                Text('Village : ${game.buildingLevels.values.fold<int>(0, (a, b) => a + b)}'
                    ' / ${buildings.length * kBuildingMaxLevel} niveaux construits'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (progress.scans.any((x) => x.kind == kindDictee)) ...[
          _DicteeCard(scans: progress.scans.where((x) => x.kind == kindDictee).toList()),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Par matière',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final m in curriculum.matieres) ...[
                  _SubjectBar(matiere: m, progress: progress),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activité des 14 derniers jours',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 110,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < days.length; i++)
                        Expanded(
                          child: Tooltip(
                            message: '${formatDate(days[i])} : ${perDay[i]} essai(s)',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: perDay[i] == 0 ? 3 : 8 + 80 * perDay[i] / maxDay,
                                    decoration: BoxDecoration(
                                      color: perDay[i] == 0
                                          ? scheme.outlineVariant
                                          : scheme.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${days[i].day}',
                                      style: text.labelSmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SubjectBar extends StatelessWidget {
  const _SubjectBar({required this.matiere, required this.progress});

  final Matiere matiere;
  final ProgressState progress;

  @override
  Widget build(BuildContext context) {
    final comps = matiere.competences;
    final acquired =
        comps.where((c) => progress.statusOf(c.id) == CompetenceStatus.acquise).length;
    final started =
        comps.where((c) => progress.statusOf(c.id) != CompetenceStatus.nonVue).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(matiere.nom)),
            Text('$acquired acquise(s) · $started abordée(s) sur ${comps.length}'),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              LinearProgressIndicator(
                value: comps.isEmpty ? 0 : started / comps.length,
                minHeight: 10,
                color: statusColor(CompetenceStatus.enCours),
                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              ),
              LinearProgressIndicator(
                value: comps.isEmpty ? 0 : acquired / comps.length,
                minHeight: 10,
                color: statusColor(CompetenceStatus.acquise),
                backgroundColor: Colors.transparent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// « Sans faute » ou « 3 erreurs (2 accords, 1 lexique) ».
String _dicteeSummary(Map<String, int> errors) {
  final total = errors.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 'sans faute';
  final parts = [
    for (final c in ErrorCategory.values)
      if ((errors[c.name] ?? 0) > 0) '${errors[c.name]} ${c.label.toLowerCase()}',
  ];
  return '$total erreur${total > 1 ? 's' : ''} (${parts.join(', ')})';
}

/// Bilan des dictées : nombre, et erreurs cumulées par catégorie, pour
/// repérer ce qu'il faut retravailler (accords, grammaire, lexique).
class _DicteeCard extends StatelessWidget {
  const _DicteeCard({required this.scans});

  final List<ScanRecord> scans;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final totals = {for (final c in ErrorCategory.values) c: 0};
    for (final s in scans) {
      for (final c in ErrorCategory.values) {
        totals[c] = totals[c]! + (s.errors[c.name] ?? 0);
      }
    }
    final totalErrors = totals.values.fold<int>(0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dictées',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${scans.length} dictée(s) · $totalErrors erreur(s) au total'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ErrorCategory.values)
                  if (c != ErrorCategory.autre || totals[c]! > 0)
                    Chip(
                      avatar: CircleAvatar(
                        backgroundColor: c.color,
                        child: Text('${totals[c]}',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      label: Text(c.label),
                      side: BorderSide(color: c.color),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
