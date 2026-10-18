import 'purity.dart';

/// Gold rate per gram (INR) for each purity, plus when it was last updated.
class GoldRates {
  const GoldRates({
    required this.perGram,
    required this.updatedAt,
    this.quotedPerGrams = 1,
  });

  /// Rates for every purity derived from the 24K rate per gram, using
  /// [Purity.percentOf24] (22K = 92%, 20K = 84%, 18K = 76%, 14K = 60%,
  /// 9K = 40%).
  factory GoldRates.fromBase24({
    required double perGram24,
    required DateTime updatedAt,
    int quotedPerGrams = 1,
  }) => GoldRates(
    perGram: {
      for (final p in Purity.values) p: perGram24 * p.percentOf24 / 100,
    },
    updatedAt: updatedAt,
    quotedPerGrams: quotedPerGrams,
  );

  /// Rates per **1 gram**; always what pricing uses.
  final Map<Purity, double> perGram;
  final DateTime updatedAt;

  /// How the user enters/reads rates: per 1 g or per 10 g (common in
  /// India, e.g. ₹70,000 / 10 g). Display only; [perGram] stays per gram.
  final int quotedPerGrams;

  /// Rate as quoted (per [quotedPerGrams] grams), rounded to the paisa.
  double? quotedRateFor(Purity purity) {
    final r = perGram[purity];
    return r == null ? null : (r * quotedPerGrams * 100).round() / 100;
  }

  String get quoteUnit => quotedPerGrams == 1 ? 'g' : '$quotedPerGrams g';

  double? rateFor(Purity purity) => perGram[purity];

  bool get isComplete => Purity.values.every((p) => (perGram[p] ?? 0) > 0);

  GoldRates copyWith({Map<Purity, double>? perGram, DateTime? updatedAt}) =>
      GoldRates(
        perGram: perGram ?? this.perGram,
        updatedAt: updatedAt ?? this.updatedAt,
        quotedPerGrams: quotedPerGrams,
      );

  Map<String, dynamic> toJson() => {
    'perGram': {for (final e in perGram.entries) e.key.name: e.value},
    'updatedAt': updatedAt.toIso8601String(),
    'quotedPerGrams': quotedPerGrams,
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
      quotedPerGrams: (json['quotedPerGrams'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GoldRates &&
      other.updatedAt == updatedAt &&
      other.quotedPerGrams == quotedPerGrams &&
      Purity.values.every((p) => other.perGram[p] == perGram[p]);

  @override
  int get hashCode => Object.hash(
    updatedAt,
    Object.hashAll(Purity.values.map((p) => perGram[p])),
  );
}
