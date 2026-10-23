import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress.dart';

const _hashKey = 'parent_pin_hash';
const _saltKey = 'parent_pin_salt';

/// Code PIN à 4 chiffres de l'espace Parent. Seule une empreinte salée est
/// stockée. C'est un verrou de confort contre un enfant curieux, pas une
/// protection forte contre quelqu'un qui contrôlerait l'appareil.
class PinRepository {
  PinRepository(this._prefs);

  final SharedPreferences _prefs;

  bool get hasPin => _prefs.getString(_hashKey) != null;

  static bool isValidFormat(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt = base64Url.encode(bytes);
    await _prefs.setString(_saltKey, salt);
    await _prefs.setString(_hashKey, _hash(pin, salt));
  }

  bool verify(String pin) {
    final salt = _prefs.getString(_saltKey);
    final stored = _prefs.getString(_hashKey);
    if (salt == null || stored == null) return false;
    return _hash(pin, salt) == stored;
  }
}

final pinRepositoryProvider = FutureProvider<PinRepository>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PinRepository(prefs);
});
