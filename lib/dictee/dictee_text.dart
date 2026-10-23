import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/curriculum.dart';
import '../core/quest_theme.dart';

/// Au-delà de ce nombre de mots, une phrase est coupée aux virgules pour
/// pouvoir être écrite par morceaux.
const int kMotsMaxParSegment = 10;

/// Découpe un texte de dictée en segments à dicter : une phrase par segment,
/// coupée aux virgules, points-virgules et deux-points quand elle est longue.
List<String> splitDictee(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];

  final sentences = normalized
      .split(RegExp(r'(?<=[.!?…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);

  final out = <String>[];
  for (final sentence in sentences) {
    if (_wordCount(sentence) <= kMotsMaxParSegment) {
      out.add(sentence);
      continue;
    }
    final parts = sentence
        .split(RegExp(r'(?<=[,;:])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // Rassemble les morceaux trop courts avec le voisin pour ne pas dicter
    // un ou deux mots isolés.
    final merged = <String>[];
    for (final p in parts) {
      if (merged.isNotEmpty && _wordCount(merged.last) < 3) {
        merged[merged.length - 1] = '${merged.last} $p';
      } else {
        merged.add(p);
      }
    }
    if (merged.length > 1 && _wordCount(merged.last) < 3) {
      final last = merged.removeLast();
      merged[merged.length - 1] = '${merged.last} $last';
    }
    out.addAll(merged);
  }
  return out;
}

int _wordCount(String s) =>
    s.split(RegExp(r'\s+')).where((w) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(w)).length;

/// Texte lu à voix haute avec la ponctuation prononcée, comme le fait un
/// enseignant (« la maison virgule grande point »).
String withSpokenPunctuation(String s) {
  const map = <String, String>{
    '…': ' points de suspension ',
    '...': ' points de suspension ',
    '?': ' point d\'interrogation ',
    '!': ' point d\'exclamation ',
    ';': ' point-virgule ',
    ':': ' deux-points ',
    ',': ' virgule ',
    '.': ' point ',
    '«': ' ouvrez les guillemets ',
    '»': ' fermez les guillemets ',
  };
  var out = s;
  map.forEach((k, v) => out = out.replaceAll(k, v));
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Texte d'une dictée, tel que lu sur une photo, saisi ou généré.
class DicteeText {
  const DicteeText({
    required this.titre,
    required this.texte,
    this.lectureIncertaine = false,
    this.questionConfirmation,
  });

  final String titre;
  final String texte;
  final bool lectureIncertaine;
  final String? questionConfirmation;
}

enum ErrorCategory {
  accord('Accords', Color(0xFF7C5CFF)),
  grammaire('Grammaire', Color(0xFF2FAE66)),
  lexique('Lexique', Color(0xFFFF8A3D)),
  autre('Autres', Color(0xFF7D8794));

  const ErrorCategory(this.label, this.color);

  final String label;
  final Color color;

  static ErrorCategory fromId(String? id) => switch (id?.toLowerCase().trim()) {
        'accord' || 'accords' => ErrorCategory.accord,
        'grammaire' || 'conjugaison' => ErrorCategory.grammaire,
        'lexique' || 'orthographe' || 'vocabulaire' => ErrorCategory.lexique,
        _ => ErrorCategory.autre,
      };
}

class DicteeError {
  const DicteeError({
    required this.motEcrit,
    required this.motAttendu,
    required this.categorie,
    required this.explication,
    this.competenceId,
  });

  final String motEcrit;
  final String motAttendu;
  final ErrorCategory categorie;
  final String explication;
  final String? competenceId;
}

/// Une compétence travaillée dans la dictée, réussie ou non.
class DicteeCompetence {
  const DicteeCompetence({required this.id, required this.reussie});

  final String id;
  final bool reussie;
}

class DicteeCorrection {
  const DicteeCorrection({
    required this.estUneDictee,
    this.lectureIncertaine = false,
    this.questionConfirmation,
    this.texteLu = '',
    this.erreurs = const [],
    this.competences = const [],
    this.message = '',
  });

  final bool estUneDictee;
  final bool lectureIncertaine;
  final String? questionConfirmation;
  final String texteLu;
  final List<DicteeError> erreurs;
  final List<DicteeCompetence> competences;
  final String message;

  int get nbErreurs => erreurs.length;

  Map<ErrorCategory, int> get parCategorie {
    final m = <ErrorCategory, int>{};
    for (final e in erreurs) {
      m[e.categorie] = (m[e.categorie] ?? 0) + 1;
    }
    return m;
  }
}

/// Ce dont l'interface a besoin pour les dictées : remplaçable dans les tests.
abstract class DicteeService {
  Future<DicteeText> extractText({
    required Uint8List image,
    required String mimeType,
  });

  Future<DicteeText> generateText({
    required QuestTheme theme,
    required Curriculum curriculum,
  });

  Future<DicteeCorrection> correct({
    required Uint8List image,
    required String mimeType,
    required String texteSource,
    required Curriculum curriculum,
  });
}

class DicteeParseException implements Exception {
  DicteeParseException(this.message);
  final String message;
  @override
  String toString() => 'DicteeParseException: $message';
}

Map<String, dynamic> _decode(String raw) {
  var s = raw.trim();
  final m = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(s);
  if (m != null) s = m.group(1)!;
  try {
    return jsonDecode(s) as Map<String, dynamic>;
  } catch (_) {
    throw DicteeParseException('Réponse illisible');
  }
}

String _req(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.trim().isEmpty) {
    throw DicteeParseException('Champ manquant ou vide : $key');
  }
  return v.trim();
}

DicteeText parseDicteeText(String raw) {
  final j = _decode(raw);
  final texte = _req(j, 'texte');
  if (splitDictee(texte).isEmpty) throw DicteeParseException('Texte vide');
  return DicteeText(
    titre: (j['titre'] as String?)?.trim().isNotEmpty == true
        ? (j['titre'] as String).trim()
        : 'Ma dictée',
    texte: texte,
    lectureIncertaine: j['lecture_incertaine'] == true,
    questionConfirmation: (j['question_de_confirmation'] as String?)?.trim(),
  );
}

/// Nombre maximal d'erreurs détaillées à l'écran : au-delà, la liste
/// décourage l'enfant plus qu'elle ne l'aide.
const int kErreursAffichees = 12;

DicteeCorrection parseDicteeCorrection(String raw, Curriculum curriculum) {
  final j = _decode(raw);
  if (j['est_une_dictee'] == false) {
    return const DicteeCorrection(estUneDictee: false);
  }

  final erreurs = <DicteeError>[];
  for (final e in (j['erreurs'] as List? ?? const [])) {
    if (e is! Map<String, dynamic>) continue;
    final ecrit = (e['mot_ecrit'] as String?)?.trim() ?? '';
    final attendu = (e['mot_attendu'] as String?)?.trim() ?? '';
    if (attendu.isEmpty) continue;
    final cid = e['competence_id'] as String?;
    erreurs.add(DicteeError(
      motEcrit: ecrit,
      motAttendu: attendu,
      categorie: ErrorCategory.fromId(e['categorie'] as String?),
      explication: (e['explication'] as String?)?.trim() ?? '',
      competenceId: cid != null && curriculum.competence(cid) != null ? cid : null,
    ));
    if (erreurs.length >= kErreursAffichees) break;
  }

  final competences = <DicteeCompetence>[];
  final seen = <String>{};
  for (final c in (j['competences'] as List? ?? const [])) {
    if (c is! Map<String, dynamic>) continue;
    final id = c['id'] as String?;
    if (id == null || curriculum.competence(id) == null || !seen.add(id)) continue;
    competences.add(DicteeCompetence(id: id, reussie: c['reussie'] == true));
  }

  return DicteeCorrection(
    estUneDictee: true,
    lectureIncertaine: j['lecture_incertaine'] == true,
    questionConfirmation: (j['question_de_confirmation'] as String?)?.trim(),
    texteLu: (j['texte_lu'] as String?)?.trim() ?? '',
    erreurs: erreurs,
    competences: competences,
    message: (j['message'] as String?)?.trim() ?? '',
  );
}
