import 'package:flutter/material.dart';

/// Couleur et icône de chaque matière, pour se repérer d'un coup d'œil.
class SubjectStyle {
  const SubjectStyle(this.icon, this.color);

  final IconData icon;
  final Color color;
}

const _styles = <String, SubjectStyle>{
  'francais': SubjectStyle(Icons.menu_book_rounded, Color(0xFFE0703C)),
  'mathematiques': SubjectStyle(Icons.calculate_rounded, Color(0xFF5B6BD6)),
  'histoire': SubjectStyle(Icons.account_balance_rounded, Color(0xFFB8402C)),
  'geographie': SubjectStyle(Icons.public_rounded, Color(0xFF2BA36B)),
  'anglais': SubjectStyle(Icons.translate_rounded, Color(0xFFC2398A)),
  'sciences': SubjectStyle(Icons.science_rounded, Color(0xFF7C4DDB)),
};

SubjectStyle subjectStyle(String matiereId) =>
    _styles[matiereId] ?? const SubjectStyle(Icons.school_rounded, Color(0xFF607D8B));
