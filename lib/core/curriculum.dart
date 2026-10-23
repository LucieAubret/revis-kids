import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Competence {
  const Competence({
    required this.id,
    required this.titre,
    required this.objectifs,
    required this.matiereId,
    required this.domaineNom,
  });

  final String id;
  final String titre;
  final List<String> objectifs;
  final String matiereId;
  final String domaineNom;
}

class Domaine {
  const Domaine({required this.id, required this.nom, required this.competences});

  final String id;
  final String nom;
  final List<Competence> competences;
}

class Matiere {
  const Matiere({required this.id, required this.nom, required this.domaines});

  final String id;
  final String nom;
  final List<Domaine> domaines;

  List<Competence> get competences =>
      [for (final d in domaines) ...d.competences];
}

/// Référentiel CM1 chargé depuis `assets/curriculum/cm1.json`.
class Curriculum {
  Curriculum(this.matieres)
      : _byId = {
          for (final m in matieres)
            for (final c in m.competences) c.id: c,
        };

  factory Curriculum.fromJson(Map<String, dynamic> json) {
    final matieres = <Matiere>[];
    for (final m in json['matieres'] as List) {
      final matiereId = m['id'] as String;
      final domaines = <Domaine>[];
      for (final d in m['domaines'] as List) {
        final nom = d['nom'] as String;
        domaines.add(Domaine(
          id: d['id'] as String,
          nom: nom,
          competences: [
            for (final c in d['competences'] as List)
              Competence(
                id: c['id'] as String,
                titre: c['titre'] as String,
                objectifs: List<String>.from(c['objectifs'] as List),
                matiereId: matiereId,
                domaineNom: nom,
              ),
          ],
        ));
      }
      matieres.add(Matiere(
        id: matiereId,
        nom: m['nom'] as String,
        domaines: domaines,
      ));
    }
    return Curriculum(matieres);
  }

  final List<Matiere> matieres;
  final Map<String, Competence> _byId;

  List<Competence> get competences => _byId.values.toList();
  Competence? competence(String id) => _byId[id];
  Matiere? matiere(String id) {
    for (final m in matieres) {
      if (m.id == id) return m;
    }
    return null;
  }
}

final curriculumProvider = FutureProvider<Curriculum>((ref) async {
  final raw = await rootBundle.loadString('assets/curriculum/cm1.json');
  return Curriculum.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});
