import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> data;

  setUpAll(() {
    data = jsonDecode(File('assets/curriculum/cm1.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  test('le référentiel couvre les six matières du CM1', () {
    final ids = (data['matieres'] as List).map((m) => m['id']).toList();
    expect(ids, [
      'francais',
      'mathematiques',
      'histoire',
      'geographie',
      'anglais',
      'sciences',
    ]);
  });

  test('chaque matière renvoie à une source officielle déclarée', () {
    final sources = (data['meta']['sources'] as Map).keys.toSet();
    for (final m in data['matieres'] as List) {
      expect(sources, contains(m['source']), reason: m['id'] as String);
    }
  });

  test('les identifiants de compétences sont uniques et ont des objectifs', () {
    final seen = <String>{};
    for (final m in data['matieres'] as List) {
      for (final d in m['domaines'] as List) {
        for (final c in d['competences'] as List) {
          final id = c['id'] as String;
          expect(seen.add(id), isTrue, reason: 'doublon $id');
          expect(id, startsWith(d['id'] as String));
          expect((c['objectifs'] as List), isNotEmpty, reason: id);
        }
      }
    }
  });
}
