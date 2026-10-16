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

/// Remembers pricing inputs that are not printed on tags so staff don't
/// retype them per item (GST rules, last ₹/ct per stone kind), and the
/// multiplier that turns a rate code printed on tags into ₹ per carat.
class PricingDefaultsRepository {
  PricingDefaultsRepository(this._store);
  final KeyValueStore _store;
  static const _key = 'pricing_defaults_v2';
  static const _multiplierKey = 'tag_rate_multiplier';

  /// Tag rate codes are ₹ per carat ÷ 100 (e.g. DIA\0.38\700 → ₹70,000/ct).
  static const defaultTagRateMultiplier = 100.0;

  Map<String, dynamic> _raw() {
    final raw = _store.get(_key);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  double get tagRateMultiplier =>
      double.tryParse(_store.get(_multiplierKey) ?? '') ??
      defaultTagRateMultiplier;

  Future<void> setTagRateMultiplier(double value) =>
      _store.put(_multiplierKey, value.toString());

  /// ₹/ct for a rate code printed on a tag, or null if it isn't a number.
  double? rateFromTagCode(String? code) {
    final n = double.tryParse(code ?? '');
    return n == null ? null : n * tagRateMultiplier;
  }

  /// Rate to pre-fill for a stone line: from its printed tag code when it
  /// has one, otherwise the last rate used for that kind.
  double? rateFor(StoneKind kind, String? code) {
    if (code != null && code.isNotEmpty) return rateFromTagCode(code);
    return ((_raw()['lastRate'] as Map?)?[kind.name] as num?)?.toDouble();
  }

  /// Defaults for a new item: remembered GST rules and, for manual entry,
  /// one empty diamond and one empty other-stone line.
  JewelleryInput load() {
    final raw = _raw();
    final gst = raw['gst'] is Map
        ? GstConfig.fromJson((raw['gst'] as Map).cast<String, dynamic>())
        : const GstConfig(ratePercent: null);
    return JewelleryInput(
      gst: gst,
      stones: [
        StoneLine(
          kind: StoneKind.diamond,
          ratePerCt: rateFor(StoneKind.diamond, null),
        ),
        StoneLine(
          kind: StoneKind.stone,
          ratePerCt: rateFor(StoneKind.stone, null),
        ),
      ],
    );
  }

  Future<void> rememberFrom(JewelleryInput input) {
    final raw = _raw();
    final lastRate = <String, dynamic>{
      ...?(raw['lastRate'] as Map?)?.cast<String, dynamic>(),
    };
    for (final line in input.stones) {
      // Rates that came from a tag code are not "typed" defaults.
      if (line.ratePerCt == null || !line.hasWeight || line.code != null) {
        continue;
      }
      lastRate[line.kind.name] = line.ratePerCt;
    }
    return _store.put(
      _key,
      jsonEncode({'gst': input.gst.toJson(), 'lastRate': lastRate}),
    );
  }
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
