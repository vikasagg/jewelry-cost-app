import '../pricing/pricing_engine.dart';
import 'gold_rates.dart';
import 'jewellery_input.dart';

/// A saved calculation. Stores a snapshot of the gold rates in force at the
/// time so that later rate changes never alter historical results.
class CalculationRecord {
  const CalculationRecord({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.input,
    required this.ratesSnapshot,
    required this.result,
    this.source = 'manual',
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final JewelleryInput input;
  final GoldRates ratesSnapshot;
  final PricingResult result;

  /// 'scan' or 'manual'.
  final String source;

  double get goldRateUsed => result.goldRatePerGram;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (input.tagNumber ?? '').toLowerCase().contains(q) ||
        (input.itemName ?? '').toLowerCase().contains(q);
  }

  CalculationRecord copyWith({
    DateTime? updatedAt,
    JewelleryInput? input,
    GoldRates? ratesSnapshot,
    PricingResult? result,
  }) => CalculationRecord(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    input: input ?? this.input,
    ratesSnapshot: ratesSnapshot ?? this.ratesSnapshot,
    result: result ?? this.result,
    source: source,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'input': input.toJson(),
    'ratesSnapshot': ratesSnapshot.toJson(),
    'result': result.toJson(),
    'source': source,
  };

  factory CalculationRecord.fromJson(Map<String, dynamic> j) =>
      CalculationRecord(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        input: JewelleryInput.fromJson(
          (j['input'] as Map).cast<String, dynamic>(),
        ),
        ratesSnapshot: GoldRates.fromJson(
          (j['ratesSnapshot'] as Map).cast<String, dynamic>(),
        ),
        result: PricingResult.fromJson(
          (j['result'] as Map).cast<String, dynamic>(),
        ),
        source: j['source'] as String? ?? 'manual',
      );
}
