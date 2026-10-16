import 'purity.dart';

/// How making charges are computed.
enum MakingMethod {
  fixed('Fixed amount (₹)'),
  percentOfGold('% of gold value');

  const MakingMethod(this.label);
  final String label;
}

/// How wastage is computed. Only one method can apply at a time.
enum WastageMethod {
  none('No wastage'),
  percent('Wastage %'),
  weight('Wastage weight (g)');

  const WastageMethod(this.label);
  final String label;
}

/// Price components that can be included in the GST taxable base.
enum PriceComponent {
  gold('Gold value'),
  diamond('Diamond value'),
  stone('Other stone value'),
  wastage('Wastage charges'),
  making('Making charges');

  const PriceComponent(this.label);
  final String label;
}

/// Configurable GST rules. No rate is hard-coded: the user supplies [ratePercent].
class GstConfig {
  const GstConfig({
    required this.ratePercent,
    this.taxable = const {
      PriceComponent.gold,
      PriceComponent.diamond,
      PriceComponent.stone,
      PriceComponent.wastage,
      PriceComponent.making,
    },
    this.makingRatePercent,
  });

  /// GST % applied to the taxable components. `null` = not yet entered.
  final double? ratePercent;

  /// Components included in the taxable base.
  final Set<PriceComponent> taxable;

  /// Optional separate GST % for making charges (e.g. job-work invoicing).
  /// When `null`, making charges (if taxable) use [ratePercent].
  final double? makingRatePercent;

  GstConfig copyWith({
    double? ratePercent,
    Set<PriceComponent>? taxable,
    double? makingRatePercent,
    bool clearMakingRate = false,
    bool clearRate = false,
  }) => GstConfig(
    ratePercent: clearRate ? null : (ratePercent ?? this.ratePercent),
    taxable: taxable ?? this.taxable,
    makingRatePercent: clearMakingRate
        ? null
        : (makingRatePercent ?? this.makingRatePercent),
  );

  Map<String, dynamic> toJson() => {
    'ratePercent': ratePercent,
    'taxable': taxable.map((c) => c.name).toList(),
    'makingRatePercent': makingRatePercent,
  };

  factory GstConfig.fromJson(Map<String, dynamic> json) => GstConfig(
    ratePercent: (json['ratePercent'] as num?)?.toDouble(),
    taxable: ((json['taxable'] as List?) ?? const [])
        .map((n) => PriceComponent.values.where((c) => c.name == n))
        .expand((e) => e)
        .toSet(),
    makingRatePercent: (json['makingRatePercent'] as num?)?.toDouble(),
  );
}

/// Everything needed to price one jewellery item. Weights/rates are nullable
/// so "not entered" can be distinguished from an explicit zero.
class JewelleryInput {
  const JewelleryInput({
    this.itemName,
    this.tagNumber,
    this.purity,
    this.goldWeight,
    this.grossWeight,
    this.diamondWeight,
    this.diamondRate,
    this.excludeDiamond = false,
    this.stoneWeight,
    this.stoneRate,
    this.excludeStone = false,
    this.makingMethod = MakingMethod.fixed,
    this.makingValue,
    this.wastageMethod = WastageMethod.none,
    this.wastagePercent,
    this.wastageWeight,
    this.gst = const GstConfig(ratePercent: null),
  });

  final String? itemName;
  final String? tagNumber;
  final Purity? purity;

  /// Gold (metal) weight in grams used for pricing.
  final double? goldWeight;

  /// Gross jewellery weight in grams (metal + stones). Informational only;
  /// never used for pricing and never auto-derived.
  final double? grossWeight;

  /// Diamond weight in carats.
  final double? diamondWeight;

  /// Diamond rate in ₹ per carat.
  final double? diamondRate;
  final bool excludeDiamond;

  /// Other stone weight in carats.
  final double? stoneWeight;

  /// Other stone rate in ₹ per carat.
  final double? stoneRate;
  final bool excludeStone;

  final MakingMethod makingMethod;

  /// ₹ amount when [makingMethod] is fixed, otherwise a percentage.
  final double? makingValue;

  final WastageMethod wastageMethod;
  final double? wastagePercent;
  final double? wastageWeight;

  final GstConfig gst;

  String get displayName {
    final parts = [
      tagNumber,
      itemName,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Untitled item' : parts.join(' · ');
  }

  JewelleryInput copyWith({
    String? itemName,
    String? tagNumber,
    Purity? purity,
    double? goldWeight,
    double? grossWeight,
    double? diamondWeight,
    double? diamondRate,
    bool? excludeDiamond,
    double? stoneWeight,
    double? stoneRate,
    bool? excludeStone,
    MakingMethod? makingMethod,
    double? makingValue,
    WastageMethod? wastageMethod,
    double? wastagePercent,
    double? wastageWeight,
    GstConfig? gst,
  }) => JewelleryInput(
    itemName: itemName ?? this.itemName,
    tagNumber: tagNumber ?? this.tagNumber,
    purity: purity ?? this.purity,
    goldWeight: goldWeight ?? this.goldWeight,
    grossWeight: grossWeight ?? this.grossWeight,
    diamondWeight: diamondWeight ?? this.diamondWeight,
    diamondRate: diamondRate ?? this.diamondRate,
    excludeDiamond: excludeDiamond ?? this.excludeDiamond,
    stoneWeight: stoneWeight ?? this.stoneWeight,
    stoneRate: stoneRate ?? this.stoneRate,
    excludeStone: excludeStone ?? this.excludeStone,
    makingMethod: makingMethod ?? this.makingMethod,
    makingValue: makingValue ?? this.makingValue,
    wastageMethod: wastageMethod ?? this.wastageMethod,
    wastagePercent: wastagePercent ?? this.wastagePercent,
    wastageWeight: wastageWeight ?? this.wastageWeight,
    gst: gst ?? this.gst,
  );

  Map<String, dynamic> toJson() => {
    'itemName': itemName,
    'tagNumber': tagNumber,
    'purity': purity?.name,
    'goldWeight': goldWeight,
    'grossWeight': grossWeight,
    'diamondWeight': diamondWeight,
    'diamondRate': diamondRate,
    'excludeDiamond': excludeDiamond,
    'stoneWeight': stoneWeight,
    'stoneRate': stoneRate,
    'excludeStone': excludeStone,
    'makingMethod': makingMethod.name,
    'makingValue': makingValue,
    'wastageMethod': wastageMethod.name,
    'wastagePercent': wastagePercent,
    'wastageWeight': wastageWeight,
    'gst': gst.toJson(),
  };

  factory JewelleryInput.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return JewelleryInput(
      itemName: j['itemName'] as String?,
      tagNumber: j['tagNumber'] as String?,
      purity: Purity.fromName(j['purity'] as String?),
      goldWeight: d('goldWeight'),
      grossWeight: d('grossWeight'),
      diamondWeight: d('diamondWeight'),
      diamondRate: d('diamondRate'),
      excludeDiamond: j['excludeDiamond'] as bool? ?? false,
      stoneWeight: d('stoneWeight'),
      stoneRate: d('stoneRate'),
      excludeStone: j['excludeStone'] as bool? ?? false,
      makingMethod: MakingMethod.values.firstWhere(
        (m) => m.name == j['makingMethod'],
        orElse: () => MakingMethod.fixed,
      ),
      makingValue: d('makingValue'),
      wastageMethod: WastageMethod.values.firstWhere(
        (m) => m.name == j['wastageMethod'],
        orElse: () => WastageMethod.none,
      ),
      wastagePercent: d('wastagePercent'),
      wastageWeight: d('wastageWeight'),
      gst: j['gst'] == null
          ? const GstConfig(ratePercent: null)
          : GstConfig.fromJson((j['gst'] as Map).cast<String, dynamic>()),
    );
  }
}
