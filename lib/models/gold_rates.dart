import 'purity.dart';

/// Gold rate per gram (INR) for each purity, plus when it was last updated.
class GoldRates {
  const GoldRates({required this.perGram, required this.updatedAt});

  final Map<Purity, double> perGram;
  final DateTime updatedAt;

  double? rateFor(Purity purity) => perGram[purity];

  bool get isComplete => Purity.values.every((p) => (perGram[p] ?? 0) > 0);

  GoldRates copyWith({Map<Purity, double>? perGram, DateTime? updatedAt}) =>
      GoldRates(
        perGram: perGram ?? this.perGram,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
    'perGram': {for (final e in perGram.entries) e.key.name: e.value},
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory GoldRates.fromJson(Map<String, dynamic> json) {
    final raw = (json['perGram'] as Map).cast<String, dynamic>();
    final map = <Purity, double>{};
    for (final e in raw.entries) {
      final p = Purity.fromName(e.key);
      if (p != null) map[p] = (e.value as num).toDouble();
    }
    return GoldRates(
      perGram: map,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GoldRates &&
      other.updatedAt == updatedAt &&
      Purity.values.every((p) => other.perGram[p] == perGram[p]);

  @override
  int get hashCode => Object.hash(
    updatedAt,
    Object.hashAll(Purity.values.map((p) => perGram[p])),
  );
}
