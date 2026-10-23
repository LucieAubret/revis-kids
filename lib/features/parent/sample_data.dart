import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';

/// Données fictives pour visualiser le tableau de bord (mode développeur
/// uniquement). Remplace les données enregistrées.
Future<void> loadSampleData(WidgetRef ref) {
  final now = DateTime.now();
  DateTime ago(int days, [int hour = 17]) =>
      DateTime(now.year, now.month, now.day, hour).subtract(Duration(days: days));

  final attempts = <Attempt>[
    // Acquise : 3 réussites sur 3 jours.
    Attempt(competenceId: 'FR.ORT.02', date: ago(9), success: true),
    Attempt(competenceId: 'FR.ORT.02', date: ago(5), success: true),
    Attempt(competenceId: 'FR.ORT.02', date: ago(1), success: true),
    // En cours, avec une capsule lue.
    Attempt(competenceId: 'FR.ORT.03', date: ago(4), success: false),
    Attempt(
        competenceId: 'FR.ORT.03',
        date: ago(4, 18),
        success: true,
        capsuleRead: true),
    Attempt(competenceId: 'MA.FRA.01', date: ago(3), success: true),
    Attempt(competenceId: 'MA.FRA.01', date: ago(2), success: false),
    Attempt(competenceId: 'MA.FRA.03', date: ago(2, 18), success: false),
    Attempt(
        competenceId: 'MA.FRA.03',
        date: ago(2, 19),
        success: true,
        capsuleRead: true),
    Attempt(competenceId: 'HI.T1.01', date: ago(6), success: true),
    Attempt(competenceId: 'HI.T1.01', date: ago(1, 16), success: true),
    Attempt(competenceId: 'HI.T1.01', date: ago(0, 8), success: true),
  ];

  final scans = <ScanRecord>[
    ScanRecord(
      id: 's1',
      date: ago(9),
      themeLabel: 'Aventures',
      matiereId: 'francais',
      competenceId: 'FR.ORT.02',
    ),
    ScanRecord(
      id: 's2',
      date: ago(3),
      themeLabel: 'Danse classique',
      matiereId: 'mathematiques',
      competenceId: 'MA.FRA.01',
    ),
    ScanRecord(
      id: 's3',
      date: ago(1),
      themeLabel: 'Histoire de France',
      matiereId: 'histoire',
      competenceId: 'HI.T1.01',
    ),
  ];

  return ref
      .read(progressProvider.notifier)
      .replaceAll(ProgressState(attempts: attempts, scans: scans));
}
