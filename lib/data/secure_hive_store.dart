import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'key_value_store.dart';

/// Hive box encrypted with AES-256. The key is generated once and kept in the
/// platform keystore (Android Keystore / iOS Keychain / WebCrypto on web).
class SecureHiveStore implements KeyValueStore {
  SecureHiveStore._(this._box);

  final Box<String> _box;

  static const _keyName = 'jewellery_cost_box_key_v1';
  static bool _hiveReady = false;

  static Future<SecureHiveStore> open(String boxName) async {
    if (!_hiveReady) {
      await Hive.initFlutter();
      _hiveReady = true;
    }
    final cipher = HiveAesCipher(await _encryptionKey());
    final box = await Hive.openBox<String>(boxName, encryptionCipher: cipher);
    return SecureHiveStore._(box);
  }

  static Future<List<int>> _encryptionKey() async {
    const storage = FlutterSecureStorage();
    if (await Hive.boxExists(_fallbackBox)) return _fallbackKey();
    try {
      final existing = await storage.read(key: _keyName);
      if (existing != null) return base64Url.decode(existing);
      final key = Hive.generateSecureKey();
      await storage.write(key: _keyName, value: base64UrlEncode(key));
      return key;
    } catch (e) {
      // Some browsers (e.g. private mode) block the secure storage backend.
      // Fall back to a fixed per-install key held by Hive itself so the app
      // still works; data is then only obfuscated, not protected.
      debugPrint('Secure key storage unavailable: $e');
      return _fallbackKey();
    }
  }

  static const _fallbackBox = 'jc_key_fallback';

  static Future<List<int>> _fallbackKey() async {
    {
      final keyBox = await Hive.openBox<String>(_fallbackBox);
      var k = keyBox.get('k');
      if (k == null) {
        k = base64UrlEncode(Hive.generateSecureKey());
        await keyBox.put('k', k);
      }
      return base64Url.decode(k);
    }
  }

  @override
  String? get(String key) => _box.get(key);

  @override
  Future<void> put(String key, String value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);

  @override
  Iterable<String> get keys => _box.keys.cast<String>();
}
