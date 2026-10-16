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

/// Whether a stone line is priced as diamond or as other stone.
enum StoneKind {
  diamond('Diamond'),
  stone('Other stone');

  const StoneKind(this.label);
  final String label;
}

/// One group of stones on a tag, e.g. `DIA\0.38\700` → 0.38 ct, code 700.
class StoneLine {
  const StoneLine({
    required this.kind,
    this.label,
    this.weightCt,
    this.ratePerCt,
    this.code,
  });

  final StoneKind kind;

  /// Label as printed on the tag ("DIA", "FANCY CUT"…), if any.
  final String? label;

  /// Weight in carats.
  final double? weightCt;

  /// Rate in ₹ per carat.
  final double? ratePerCt;

  /// Rate code printed after the weight (e.g. 700 in `DIA\\0.38\\700`).
  /// It pre-fills [ratePerCt] (code × tag rate multiplier, ₹70,000/ct by
  /// default); the calculation always uses [ratePerCt].
  final String? code;

  String get displayName {
    final l = label?.trim();
    return (l == null || l.isEmpty) ? kind.label : l;
  }

  bool get hasWeight => (weightCt ?? 0) > 0;

  StoneLine copyWith({
    StoneKind? kind,
    String? label,
    double? weightCt,
    double? ratePerCt,
    String? code,
  }) => StoneLine(
    kind: kind ?? this.kind,
    label: label ?? this.label,
    weightCt: weightCt ?? this.weightCt,
    ratePerCt: ratePerCt ?? this.ratePerCt,
    code: code ?? this.code,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'label': label,
    'weightCt': weightCt,
    'ratePerCt': ratePerCt,
    'code': code,
  };

  factory StoneLine.fromJson(Map<String, dynamic> j) => StoneLine(
    kind: StoneKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => StoneKind.diamond,
    ),
    label: j['label'] as String?,
    weightCt: (j['weightCt'] as num?)?.toDouble(),
    ratePerCt: (j['ratePerCt'] as num?)?.toDouble(),
    code: j['code'] as String?,
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
    this.stones = const [],
    this.excludeDiamond = false,
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

  /// Gold (metal / net) weight in grams used for pricing.
  final double? goldWeight;

  /// Gross jewellery weight in grams (metal + stones). Informational only;
  /// never used for pricing and never auto-derived.
  final double? grossWeight;

  /// Diamond and other-stone groups, each with its own weight and rate.
  final List<StoneLine> stones;

  final bool excludeDiamond;
  final bool excludeStone;

  final MakingMethod makingMethod;

  /// ₹ amount when [makingMethod] is fixed, otherwise a percentage.
  final double? makingValue;

  final WastageMethod wastageMethod;
  final double? wastagePercent;
  final double? wastageWeight;

  final GstConfig gst;

  Iterable<StoneLine> linesOf(StoneKind kind) =>
      stones.where((s) => s.kind == kind);

  /// Total diamond weight in carats.
  double get diamondWeight =>
      linesOf(StoneKind.diamond).fold(0.0, (a, s) => a + (s.weightCt ?? 0));

  /// Total other-stone weight in carats.
  double get stoneWeight =>
      linesOf(StoneKind.stone).fold(0.0, (a, s) => a + (s.weightCt ?? 0));

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
    List<StoneLine>? stones,
    bool? excludeDiamond,
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
    stones: stones ?? this.stones,
    excludeDiamond: excludeDiamond ?? this.excludeDiamond,
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
    'stones': stones.map((s) => s.toJson()).toList(),
    'excludeDiamond': excludeDiamond,
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
    final stones = j['stones'] is List
        ? (j['stones'] as List)
              .map(
                (s) => StoneLine.fromJson((s as Map).cast<String, dynamic>()),
              )
              .toList()
        : <StoneLine>[
            // Records saved before multi-line stones existed.
            if (d('diamondWeight') != null || d('diamondRate') != null)
              StoneLine(
                kind: StoneKind.diamond,
                weightCt: d('diamondWeight'),
                ratePerCt: d('diamondRate'),
              ),
            if (d('stoneWeight') != null || d('stoneRate') != null)
              StoneLine(
                kind: StoneKind.stone,
                weightCt: d('stoneWeight'),
                ratePerCt: d('stoneRate'),
              ),
          ];
    return JewelleryInput(
      itemName: j['itemName'] as String?,
      tagNumber: j['tagNumber'] as String?,
      purity: Purity.fromName(j['purity'] as String?),
      goldWeight: d('goldWeight'),
      grossWeight: d('grossWeight'),
      stones: stones,
      excludeDiamond: j['excludeDiamond'] as bool? ?? false,
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
