import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/curriculum.dart';
import '../data/progress.dart';

/// Nombre de compétences « acquises » par matière : c'est ce qui débloque les
/// niveaux supérieurs des bâtiments du village.
final acquiredByMatiereProvider = FutureProvider<Map<String, int>>((ref) async {
  final curriculum = await ref.watch(curriculumProvider.future);
  final progress = await ref.watch(progressProvider.future);
  return {
    for (final m in curriculum.matieres)
      m.id: m.competences
          .where((c) => progress.statusOf(c.id) == CompetenceStatus.acquise)
          .length,
  };
});
