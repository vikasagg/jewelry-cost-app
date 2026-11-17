import 'key_value_store.dart';

/// Wraps the phone's storage and notes every change to data that is shared
/// with the shop PC, so it can be sent there (see DataSync). Changes that
/// come from the PC are written with [putRemote]/[deleteRemote] and are
/// not noted.
class SyncingStore implements KeyValueStore {
  SyncingStore(this._inner, {required this.isShared});

  final KeyValueStore _inner;

  /// Whether a key's data is shared with the shop PC.
  final bool Function(String key) isShared;

  /// Called after a shared key changed on this phone.
  void Function(String key)? onChange;

  static const changedPrefix = 'sync_changed_';
  int _seq = 0;

  String _mark() => '${DateTime.now().microsecondsSinceEpoch}.${_seq++}';

  @override
  String? get(String key) => _inner.get(key);

  @override
  Iterable<String> get keys => _inner.keys;

  @override
  Future<void> put(String key, String value) async {
    await _inner.put(key, value);
    await _changed(key);
  }

  @override
  Future<void> delete(String key) async {
    final had = _inner.get(key) != null;
    await _inner.delete(key);
    if (had) await _changed(key);
  }

  Future<void> _changed(String key) async {
    if (!isShared(key)) return;
    await _inner.put('$changedPrefix$key', _mark());
    onChange?.call(key);
  }

  /// Writes data received from the shop PC (not sent back).
  Future<void> putRemote(String key, String value) => _inner.put(key, value);

  Future<void> deleteRemote(String key) => _inner.delete(key);

  /// Shared keys changed here and not yet sent.
  List<String> get changedKeys => [
    for (final k in _inner.keys.where((k) => k.startsWith(changedPrefix)))
      k.substring(changedPrefix.length),
  ];

  String? changeMark(String key) => _inner.get('$changedPrefix$key');

  /// Clears the "not sent" note, unless the key changed again meanwhile.
  Future<void> markSent(String key, String? mark) async {
    if (mark != null && changeMark(key) == mark) {
      await _inner.delete('$changedPrefix$key');
    }
  }

  /// Notes [key] as changed (e.g. to send everything once).
  Future<void> markChanged(String key) => _changed(key);
}
