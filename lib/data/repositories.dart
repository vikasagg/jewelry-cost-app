import 'dart:convert';

import '../models/calculation_record.dart';
import '../models/gold_rates.dart';
import '../models/jewellery_input.dart';
import 'key_value_store.dart';

/// Persists the current gold rates.
class RatesRepository {
  RatesRepository(this._store);
  final KeyValueStore _store;
  static const _key = 'gold_rates';

  GoldRates? load() {
    final raw = _store.get(_key);
    if (raw == null) return null;
    try {
      return GoldRates.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(GoldRates rates) =>
      _store.put(_key, jsonEncode(rates.toJson()));
}

/// Defaults for a new item and the multiplier that turns a rate code
/// printed on tags into ₹ per carat. Nothing from a previous item is carried
/// over: every scan starts clean.
class PricingDefaultsRepository {
  PricingDefaultsRepository(this._store);
  final KeyValueStore _store;
  static const _counterKey = 'dj_tag_counter';

  /// Tag rate code × multiplier = ₹ per carat. Diamonds and polki use ×100
  /// (DIA\0.38\700 → ₹70,000/ct); stones use ×10 (Stn\0.25\600 → ₹6,000/ct).
  static const defaultMultipliers = {
    StoneKind.diamond: 100.0,
    StoneKind.stone: 10.0,
    StoneKind.polki: 100.0,
  };

  /// GST % pre-filled on every new item (editable per item).
  static const defaultGstPercent = 3.0;

  /// Prefix of the automatic tag number, e.g. DJ-0001.
  static const tagPrefix = 'DJ-';

  // Diamond keeps the original key so earlier settings carry over.
  static String _multiplierKey(StoneKind kind) => kind == StoneKind.diamond
      ? 'tag_rate_multiplier'
      : 'tag_rate_multiplier_${kind.name}';

  double tagRateMultiplier(StoneKind kind) =>
      double.tryParse(_store.get(_multiplierKey(kind)) ?? '') ??
      defaultMultipliers[kind]!;

  Future<void> setTagRateMultiplier(StoneKind kind, double value) =>
      _store.put(_multiplierKey(kind), value.toString());

  /// ₹/ct for a rate code printed on a tag, or null if it isn't a number.
  double? rateFromTagCode(StoneKind kind, String? code) {
    final n = double.tryParse(code ?? '');
    return n == null ? null : n * tagRateMultiplier(kind);
  }

  /// Rate to pre-fill for a stone line: only from its printed tag code.
  double? rateFor(StoneKind kind, String? code) => rateFromTagCode(kind, code);

  int get _lastTagNumber => int.tryParse(_store.get(_counterKey) ?? '') ?? 0;

  /// Next automatic tag number, e.g. "DJ-0001".
  String get nextTagNumber =>
      '$tagPrefix${(_lastTagNumber + 1).toString().padLeft(4, '0')}';

  /// Moves the counter past [tagNumber] if it is an automatic DJ- number.
  Future<void> recordTagNumber(String? tagNumber) async {
    final m = RegExp(
      r'^DJ-(\d+)$',
      caseSensitive: false,
    ).firstMatch(tagNumber?.trim() ?? '');
    if (m == null) return;
    final n = int.parse(m.group(1)!);
    if (n > _lastTagNumber) await _store.put(_counterKey, '$n');
  }

  /// A clean new item: GST 3%, making per gram (empty), and for manual
  /// entry one empty diamond and one empty stone line.
  JewelleryInput load() => const JewelleryInput(
    gst: GstConfig(ratePercent: defaultGstPercent),
    stones: [
      StoneLine(kind: StoneKind.diamond),
      StoneLine(kind: StoneKind.stone),
    ],
  );
}

/// Persists saved calculations, one key per record.
class HistoryRepository {
  HistoryRepository(this._store);
  final KeyValueStore _store;
  static const _prefix = 'calc_';

  /// Newest first.
  List<CalculationRecord> all() {
    final out = <CalculationRecord>[];
    for (final k in _store.keys.where((k) => k.startsWith(_prefix))) {
      try {
        out.add(
          CalculationRecord.fromJson(
            jsonDecode(_store.get(k)!) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // Skip corrupt entries rather than failing the whole list.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  List<CalculationRecord> search(String query) =>
      all().where((r) => r.matches(query)).toList();

  CalculationRecord? byId(String id) {
    final raw = _store.get('$_prefix$id');
    return raw == null
        ? null
        : CalculationRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CalculationRecord r) =>
      _store.put('$_prefix${r.id}', jsonEncode(r.toJson()));

  Future<void> delete(String id) => _store.delete('$_prefix$id');
}
