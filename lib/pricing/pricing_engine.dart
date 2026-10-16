import '../core/money.dart';
import '../models/jewellery_input.dart';
import '../models/purity.dart';

/// A problem that prevents a calculation, tied to the input field at fault.
class PricingIssue {
  const PricingIssue(this.field, this.message);

  /// Field key, matching the keys used by the details form.
  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

/// One GST line: rate applied to a base.
class GstLine {
  const GstLine({
    required this.label,
    required this.components,
    required this.basePaise,
    required this.ratePercent,
    required this.amountPaise,
  });

  final String label;
  final List<PriceComponent> components;
  final int basePaise;
  final double ratePercent;
  final int amountPaise;

  Map<String, dynamic> toJson() => {
    'label': label,
    'components': components.map((c) => c.name).toList(),
    'basePaise': basePaise,
    'ratePercent': ratePercent,
    'amountPaise': amountPaise,
  };

  factory GstLine.fromJson(Map<String, dynamic> j) => GstLine(
    label: j['label'] as String,
    components: (j['components'] as List)
        .map((n) => PriceComponent.values.firstWhere((c) => c.name == n))
        .toList(),
    basePaise: j['basePaise'] as int,
    ratePercent: (j['ratePercent'] as num).toDouble(),
    amountPaise: j['amountPaise'] as int,
  );
}

/// Fully itemised result. All amounts are integer paise.
class PricingResult {
  const PricingResult({
    required this.purity,
    required this.goldRatePerGram,
    required this.goldValuePaise,
    required this.diamondValuePaise,
    required this.stoneValuePaise,
    this.stoneLinePaise = const [],
    required this.wastagePaise,
    required this.makingPaise,
    required this.subtotalPaise,
    required this.taxableBasePaise,
    required this.gstLines,
    required this.gstPaise,
    required this.totalPaise,
    required this.notes,
  });

  final Purity purity;
  final double goldRatePerGram;
  final int goldValuePaise;
  final int diamondValuePaise;
  final int stoneValuePaise;

  /// Value of each entry in [JewelleryInput.stones], in the same order.
  final List<int> stoneLinePaise;
  final int wastagePaise;
  final int makingPaise;
  final int subtotalPaise;
  final int taxableBasePaise;
  final List<GstLine> gstLines;
  final int gstPaise;
  final int totalPaise;

  /// Human-readable explanations of how each figure was derived.
  final List<String> notes;

  int componentPaise(PriceComponent c) => switch (c) {
    PriceComponent.gold => goldValuePaise,
    PriceComponent.diamond => diamondValuePaise,
    PriceComponent.stone => stoneValuePaise,
    PriceComponent.wastage => wastagePaise,
    PriceComponent.making => makingPaise,
  };

  Map<String, dynamic> toJson() => {
    'purity': purity.name,
    'goldRatePerGram': goldRatePerGram,
    'goldValuePaise': goldValuePaise,
    'diamondValuePaise': diamondValuePaise,
    'stoneValuePaise': stoneValuePaise,
    'stoneLinePaise': stoneLinePaise,
    'wastagePaise': wastagePaise,
    'makingPaise': makingPaise,
    'subtotalPaise': subtotalPaise,
    'taxableBasePaise': taxableBasePaise,
    'gstLines': gstLines.map((l) => l.toJson()).toList(),
    'gstPaise': gstPaise,
    'totalPaise': totalPaise,
    'notes': notes,
  };

  factory PricingResult.fromJson(Map<String, dynamic> j) => PricingResult(
    purity: Purity.fromName(j['purity'] as String)!,
    goldRatePerGram: (j['goldRatePerGram'] as num).toDouble(),
    goldValuePaise: j['goldValuePaise'] as int,
    diamondValuePaise: j['diamondValuePaise'] as int,
    stoneValuePaise: j['stoneValuePaise'] as int,
    stoneLinePaise: ((j['stoneLinePaise'] as List?) ?? const []).cast<int>(),
    wastagePaise: j['wastagePaise'] as int,
    makingPaise: j['makingPaise'] as int,
    subtotalPaise: j['subtotalPaise'] as int,
    taxableBasePaise: j['taxableBasePaise'] as int,
    gstLines: (j['gstLines'] as List)
        .map((l) => GstLine.fromJson((l as Map).cast<String, dynamic>()))
        .toList(),
    gstPaise: j['gstPaise'] as int,
    totalPaise: j['totalPaise'] as int,
    notes: (j['notes'] as List).cast<String>(),
  );
}

/// Either a result or the list of issues that block it.
class PricingOutcome {
  const PricingOutcome._(this.result, this.issues);

  factory PricingOutcome.ok(PricingResult r) => PricingOutcome._(r, const []);
  factory PricingOutcome.failed(List<PricingIssue> issues) =>
      PricingOutcome._(null, List.unmodifiable(issues));

  final PricingResult? result;
  final List<PricingIssue> issues;

  bool get isOk => result != null;
}

/// Pure, side-effect-free jewellery pricing engine.
///
/// Formulas:
///  * Gold value     = gold weight (g) × gold rate/g for the selected purity
///  * Diamond value  = Σ diamond lines (weight ct × rate/ct)
///  * Stone value    = Σ other-stone lines (weight ct × rate/ct)
///  * Wastage        = gold value × % / 100   OR   wastage g × gold rate/g
///  * Making         = ₹/g × gold weight  OR  fixed ₹  OR  gold value × % / 100
///  * Subtotal       = sum of the above
///  * GST            = taxable base × GST % / 100 (per configured rule)
///  * Total          = subtotal + GST
///
/// Each line item is rounded to the paisa before summing, so the displayed
/// line items always add up exactly to the displayed totals.
/// No purity adjustment is applied on top of the per-purity rate.
class PricingEngine {
  const PricingEngine();

  /// [goldRates] maps purity → ₹/g (typically a saved snapshot).
  PricingOutcome calculate(
    JewelleryInput input,
    Map<Purity, double> goldRates,
  ) {
    final issues = validate(input, goldRates);
    if (issues.isNotEmpty) return PricingOutcome.failed(issues);

    final purity = input.purity!;
    final rate = goldRates[purity]!;
    final notes = <String>[];

    final goldWeight = input.goldWeight!;
    final gold = toPaise(goldWeight * rate);
    notes.add(
      'Gold: ${goldWeight.toStringAsFixed(3)} g × '
      '${formatInr(rate)}/g (${purity.label})',
    );

    // Each stone line is priced and rounded on its own, then summed.
    final linePaise = <int>[];
    var diamond = 0;
    var stone = 0;
    for (final line in input.stones) {
      final excluded = line.kind == StoneKind.diamond
          ? input.excludeDiamond
          : input.excludeStone;
      if (excluded || !line.hasWeight) {
        linePaise.add(0);
        continue;
      }
      final v = toPaise(line.weightCt! * line.ratePerCt!);
      linePaise.add(v);
      if (line.kind == StoneKind.diamond) {
        diamond += v;
      } else {
        stone += v;
      }
      notes.add(
        '${line.displayName}: ${line.weightCt!.toStringAsFixed(2)} ct × '
        '${formatInr(line.ratePerCt!)}/ct',
      );
    }
    if (input.excludeDiamond && input.diamondWeight > 0) {
      notes.add('Diamond value excluded by user');
    }
    if (input.excludeStone && input.stoneWeight > 0) {
      notes.add('Other stone value excluded by user');
    }

    var wastage = 0;
    switch (input.wastageMethod) {
      case WastageMethod.none:
        break;
      case WastageMethod.percent:
        wastage = _percentOf(gold, input.wastagePercent!);
        notes.add(
          'Wastage: ${formatPercent(input.wastagePercent!)}% of gold value',
        );
      case WastageMethod.weight:
        wastage = toPaise(input.wastageWeight! * rate);
        notes.add(
          'Wastage: ${input.wastageWeight!.toStringAsFixed(3)} g × '
          '${formatInr(rate)}/g',
        );
    }

    final int making;
    switch (input.makingMethod) {
      case MakingMethod.perGram:
        // Making charge per gram × gold (net) weight, e.g. 1200 × 1.35 g.
        making = toPaise(input.makingValue! * goldWeight);
        notes.add(
          'Making: ${formatInr(input.makingValue!)}/g × '
          '${goldWeight.toStringAsFixed(3)} g',
        );
      case MakingMethod.fixed:
        making = toPaise(input.makingValue!);
        notes.add('Making: fixed ${formatInr(input.makingValue!)}');
      case MakingMethod.percentOfGold:
        making = _percentOf(gold, input.makingValue!);
        notes.add(
          'Making: ${formatPercent(input.makingValue!)}% of gold value',
        );
    }

    final components = {
      PriceComponent.gold: gold,
      PriceComponent.diamond: diamond,
      PriceComponent.stone: stone,
      PriceComponent.wastage: wastage,
      PriceComponent.making: making,
    };
    final subtotal = components.values.fold<int>(0, (a, b) => a + b);

    // GST
    final gst = input.gst;
    final lines = <GstLine>[];
    final separateMaking =
        gst.makingRatePercent != null &&
        gst.taxable.contains(PriceComponent.making);
    final mainComponents = PriceComponent.values
        .where((c) => gst.taxable.contains(c))
        .where((c) => !(separateMaking && c == PriceComponent.making))
        .toList();
    if (mainComponents.isNotEmpty) {
      final base = mainComponents.fold<int>(0, (a, c) => a + components[c]!);
      lines.add(
        GstLine(
          label: separateMaking ? 'GST on goods' : 'GST',
          components: mainComponents,
          basePaise: base,
          ratePercent: gst.ratePercent!,
          amountPaise: _percentOf(base, gst.ratePercent!),
        ),
      );
    }
    if (separateMaking) {
      lines.add(
        GstLine(
          label: 'GST on making charges',
          components: const [PriceComponent.making],
          basePaise: making,
          ratePercent: gst.makingRatePercent!,
          amountPaise: _percentOf(making, gst.makingRatePercent!),
        ),
      );
    }
    final taxableBase = lines.fold<int>(0, (a, l) => a + l.basePaise);
    final gstTotal = lines.fold<int>(0, (a, l) => a + l.amountPaise);
    if (lines.isEmpty) {
      notes.add('No components selected as taxable — GST is ₹0.00');
    }

    return PricingOutcome.ok(
      PricingResult(
        purity: purity,
        goldRatePerGram: rate,
        goldValuePaise: gold,
        diamondValuePaise: diamond,
        stoneValuePaise: stone,
        stoneLinePaise: linePaise,
        wastagePaise: wastage,
        makingPaise: making,
        subtotalPaise: subtotal,
        taxableBasePaise: taxableBase,
        gstLines: lines,
        gstPaise: gstTotal,
        totalPaise: subtotal + gstTotal,
        notes: notes,
      ),
    );
  }

  /// Returns every problem with [input]; empty means it can be priced.
  List<PricingIssue> validate(
    JewelleryInput input,
    Map<Purity, double> goldRates,
  ) {
    final issues = <PricingIssue>[];

    void nonNegative(String field, double? v, String label) {
      if (v != null && (v.isNaN || v.isInfinite || v < 0)) {
        issues.add(PricingIssue(field, '$label cannot be negative'));
      }
    }

    if (input.purity == null) {
      issues.add(const PricingIssue('purity', 'Select the gold purity'));
    } else {
      final rate = goldRates[input.purity];
      if (rate == null || rate <= 0 || rate.isNaN) {
        issues.add(
          PricingIssue(
            'purity',
            'No saved gold rate for ${input.purity!.label}. Update gold rates first',
          ),
        );
      }
    }

    final gw = input.goldWeight;
    if (gw == null) {
      issues.add(const PricingIssue('goldWeight', 'Gold weight is required'));
    } else if (gw <= 0 || gw.isNaN) {
      issues.add(
        const PricingIssue('goldWeight', 'Gold weight must be greater than 0'),
      );
    }
    nonNegative('grossWeight', input.grossWeight, 'Gross weight');

    for (var i = 0; i < input.stones.length; i++) {
      final line = input.stones[i];
      final name = line.displayName;
      nonNegative('stone.$i.weight', line.weightCt, '$name weight');
      nonNegative('stone.$i.rate', line.ratePerCt, '$name rate');
      final excluded = line.kind == StoneKind.diamond
          ? input.excludeDiamond
          : input.excludeStone;
      if (line.hasWeight && !excluded && line.ratePerCt == null) {
        issues.add(
          PricingIssue(
            'stone.$i.rate',
            line.kind == StoneKind.diamond
                ? '$name weight is present: enter a rate per carat or exclude diamond value'
                : '$name weight is present: enter a rate per carat (0 allowed) or exclude stone value',
          ),
        );
      }
    }

    if (input.makingValue == null) {
      issues.add(
        const PricingIssue(
          'makingValue',
          'Enter making charges (0 if not applicable)',
        ),
      );
    } else {
      nonNegative('makingValue', input.makingValue, 'Making charges');
    }

    switch (input.wastageMethod) {
      case WastageMethod.none:
        break;
      case WastageMethod.percent:
        if (input.wastagePercent == null) {
          issues.add(
            const PricingIssue('wastagePercent', 'Enter wastage percentage'),
          );
        }
        nonNegative('wastagePercent', input.wastagePercent, 'Wastage %');
      case WastageMethod.weight:
        if (input.wastageWeight == null) {
          issues.add(
            const PricingIssue(
              'wastageWeight',
              'Enter wastage weight in grams',
            ),
          );
        }
        nonNegative('wastageWeight', input.wastageWeight, 'Wastage weight');
    }

    final gst = input.gst;
    final needsMainRate = gst.taxable.any(
      (c) => !(c == PriceComponent.making && gst.makingRatePercent != null),
    );
    if (needsMainRate && gst.ratePercent == null) {
      issues.add(
        const PricingIssue('gstRate', 'Enter the GST percentage (0 allowed)'),
      );
    }
    nonNegative('gstRate', gst.ratePercent, 'GST %');
    nonNegative('gstMakingRate', gst.makingRatePercent, 'GST % on making');

    return issues;
  }

  int _percentOf(int basePaise, double percent) =>
      toPaise(basePaise * percent / 100 / 100);
}
