/// Retire d'une clé collée tout ce qui n'en fait pas partie : espaces, retours
/// à la ligne, caractères invisibles (espace insécable, largeur nulle), et
/// guillemets ou apostrophes autour.
String sanitizeApiKey(String raw) {
  final noInvisible = raw.replaceAll(
    RegExp(r'[\s\u00A0\u200B-\u200D\u2060\uFEFF]'),
    '',
  );
  return noInvisible.replaceAll(RegExp('^["\'`“”‘’]+|["\'`“”‘’]+\$'), '');
}

/// Une clé API ne contient que des lettres, chiffres, points, tirets et soulignés.
/// Tout autre caractère rend l'en-tête HTTP invalide.
bool isValidKeyFormat(String key) =>
    key.isNotEmpty && RegExp(r'^[A-Za-z0-9._~\-]+$').hasMatch(key);
