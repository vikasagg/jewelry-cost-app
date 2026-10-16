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

/// Remembers the last-used pricing inputs that are not printed on tags
/// (diamond/stone rates, GST rules) so staff don't retype them per item.
class PricingDefaultsRepository {
  PricingDefaultsRepository(this._store);
  final KeyValueStore _store;
  static const _key = 'pricing_defaults';

  JewelleryInput load() {
    final raw = _store.get(_key);
    if (raw == null) return const JewelleryInput();
    try {
      return JewelleryInput.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const JewelleryInput();
    }
  }

  Future<void> rememberFrom(JewelleryInput input) => _store.put(
    _key,
    jsonEncode(
      JewelleryInput(
        diamondRate: input.diamondRate,
        stoneRate: input.stoneRate,
        gst: input.gst,
      ).toJson(),
    ),
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
