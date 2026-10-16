/// Minimal string key/value storage, so repositories are testable without
/// platform plugins.
abstract class KeyValueStore {
  String? get(String key);
  Future<void> put(String key, String value);
  Future<void> delete(String key);
  Iterable<String> get keys;
}

/// In-memory store used by tests.
class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  String? get(String key) => _data[key];

  @override
  Future<void> put(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Iterable<String> get keys => _data.keys;
}
