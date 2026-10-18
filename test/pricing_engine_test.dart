import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';

import 'package:jewellery_cost/pricing/pricing_engine.dart';

StoneLine dia(double? w, double? r) =>
    StoneLine(kind: StoneKind.diamond, label: 'DIA', weightCt: w, ratePerCt: r);
StoneLine stn(double? w, double? r) =>
    StoneLine(kind: StoneKind.stone, label: 'Stone', weightCt: w, ratePerCt: r);

const rates = {
  Purity.k9: 2800.0,
  Purity.k14: 4100.0,
  Purity.k18: 5300.0,
  Purity.k20: 5880.0,
  Purity.k22: 6450.0,
  Purity.k24: 7000.0,
};

const allTaxable3 = GstConfig(ratePercent: 3);

JewelleryInput base({
  Purity purity = Purity.k18,
  double? goldWeight = 10,
  double? makingValue = 0,
  GstConfig gst = allTaxable3,
}) => JewelleryInput(
  purity: purity,
  goldWeight: goldWeight,
  makingMethod: MakingMethod.fixed,
  makingValue: makingValue,
  gst: gst,
);

void main() {
  const engine = PricingEngine();

  PricingResult ok(JewelleryInput i, [Map<Purity, double> r = rates]) {
    final o = engine.calculate(i, r);
    expect(o.issues, isEmpty, reason: o.issues.join('\n'));
    return o.result!;
  }

  group('gold value', () {
    test(
      'uses the saved rate of the selected purity with no extra purity factor',
      () {
        for (final p in Purity.values) {
          final r = ok(base(purity: p, gst: const GstConfig(ratePercent: 0)));
          expect(r.goldRatePerGram, rates[p]);
          expect(r.goldValuePaise, (rates[p]! * 10 * 100).round());
        }
      },
    );

    test('fractional gold weight is rounded to the paisa', () {
      final r = ok(
        base(goldWeight: 3.457, gst: const GstConfig(ratePercent: 0)),
      );
      // 3.457 × 5300 = 18322.1
      expect(r.goldValuePaise, 1832210);
    });

    test('reproduces the sample summary screen', () {
      // Sample UI: 18K, 10 g @ ₹7,000/g, 0.50 ct @ ₹30,000, 0.20 ct @ ₹5,000,
      // making 10% of gold, wastage 5%, GST 3%.
      final r = ok(
        JewelleryInput(
          purity: Purity.k18,
          goldWeight: 10,

          makingMethod: MakingMethod.percentOfGold,
          makingValue: 10,
          wastageMethod: WastageMethod.percent,
          wastagePercent: 5,
          gst: allTaxable3,
          stones: [dia(0.5, 30000), stn(0.2, 5000)],
        ),
        {...rates, Purity.k18: 7000},
      );
      expect(r.goldValuePaise, 7000000);
      expect(r.diamondValuePaise, 1500000);
      expect(r.stoneValuePaise, 100000);
      expect(r.makingPaise, 700000);
      expect(r.wastagePaise, 350000);
      expect(r.subtotalPaise, 9650000);
      expect(r.gstPaise, 289500);
      expect(r.totalPaise, 9939500); // ₹99,395.00
    });
  });

  group('validation', () {
    test('missing gold weight is reported', () {
      final o = engine.calculate(base(goldWeight: null), rates);
      expect(o.isOk, isFalse);
      expect(o.issues.map((i) => i.field), contains('goldWeight'));
    });

    test('zero or negative gold weight is rejected', () {
      expect(engine.calculate(base(goldWeight: 0), rates).isOk, isFalse);
      expect(engine.calculate(base(goldWeight: -1), rates).isOk, isFalse);
    });

    test('missing purity is reported', () {
      final o = engine.calculate(
        const JewelleryInput(goldWeight: 5, makingValue: 0, gst: allTaxable3),
        rates,
      );
      expect(o.issues.map((i) => i.field), contains('purity'));
    });

    test('missing or non-positive gold rate for purity is reported', () {
      final o = engine.calculate(base(), {...rates}..remove(Purity.k18));
      expect(o.issues.single.field, 'purity');
      final o2 = engine.calculate(base(), {...rates, Purity.k18: 0});
      expect(o2.issues.single.field, 'purity');
    });

    test('negative weights and rates are rejected', () {
      final o = engine.calculate(
        base().copyWith(grossWeight: -3, stones: [dia(-0.1, -5), stn(-1, -2)]),
        rates,
      );
      expect(
        o.issues.map((i) => i.field).toSet(),
        containsAll([
          'stone.0.weight',
          'stone.0.rate',
          'stone.1.weight',
          'stone.1.rate',
          'grossWeight',
        ]),
      );
    });

    test('negative making, wastage and GST rejected', () {
      final o = engine.calculate(
        JewelleryInput(
          purity: Purity.k22,
          goldWeight: 5,
          makingValue: -1,
          wastageMethod: WastageMethod.percent,
          wastagePercent: -2,
          gst: const GstConfig(ratePercent: -3),
        ),
        rates,
      );
      expect(
        o.issues.map((i) => i.field).toSet(),
        containsAll(['makingValue', 'wastagePercent', 'gstRate']),
      );
    });

    test('GST rate must be entered (no hard-coded default)', () {
      final o = engine.calculate(
        base(gst: const GstConfig(ratePercent: null)),
        rates,
      );
      expect(o.issues.single.field, 'gstRate');
    });

    test('making charges must be entered (0 allowed)', () {
      expect(
        engine.calculate(base(makingValue: null), rates).issues.single.field,
        'makingValue',
      );
      expect(engine.calculate(base(makingValue: 0), rates).isOk, isTrue);
    });
  });

  group('diamond and stone (carats)', () {
    test('diamond value = ct × rate/ct', () {
      final r = ok(base().copyWith(stones: [dia(0.37, 65000)]));
      expect(r.diamondValuePaise, 2405000);
    });

    test('stone value = ct × rate/ct', () {
      final r = ok(base().copyWith(stones: [stn(1.25, 1200)]));
      expect(r.stoneValuePaise, 150000);
    });

    test('missing diamond rate blocks the calculation', () {
      final o = engine.calculate(
        base().copyWith(stones: [dia(0.5, null)]),
        rates,
      );
      expect(o.issues.single.field, 'stone.0.rate');
    });

    test('diamond can be explicitly excluded instead', () {
      final r = ok(
        base().copyWith(excludeDiamond: true, stones: [dia(0.5, null)]),
      );
      expect(r.diamondValuePaise, 0);
      expect(r.notes.join(), contains('excluded'));
    });

    test('missing stone rate blocks; zero stone rate is allowed', () {
      expect(
        engine
            .calculate(base().copyWith(stones: [stn(0.2, null)]), rates)
            .issues
            .single
            .field,
        'stone.0.rate',
      );
      final r = ok(base().copyWith(stones: [stn(0.2, 0)]));
      expect(r.stoneValuePaise, 0);
    });

    test('stone can be excluded', () {
      final r = ok(
        base().copyWith(excludeStone: true, stones: [stn(0.2, null)]),
      );
      expect(r.stoneValuePaise, 0);
    });

    test('rate without weight contributes nothing', () {
      final r = ok(base().copyWith(stones: [dia(null, 50000)]));
      expect(r.diamondValuePaise, 0);
    });
  });

  group('making charges', () {
    test('fixed amount', () {
      final r = ok(base(makingValue: 2499.5));
      expect(r.makingPaise, 249950);
    });

    test('percentage of gold value', () {
      final r = ok(
        base(
          makingValue: 12.5,
        ).copyWith(makingMethod: MakingMethod.percentOfGold),
      );
      // 12.5% of 53,000
      expect(r.makingPaise, 662500);
    });
  });

  group('making charges per gram', () {
    test('rate per gram × gold (net) weight: 1200 × 1.35 g = ₹1,620', () {
      final r = ok(
        base(
          goldWeight: 1.35,
        ).copyWith(makingMethod: MakingMethod.perGram, makingValue: 1200),
      );
      expect(r.makingPaise, 162000);
    });

    test('real tag 08: 1200/g × 5.886 g = ₹7,063.20', () {
      final r = ok(
        base(
          goldWeight: 5.886,
        ).copyWith(makingMethod: MakingMethod.perGram, makingValue: 1200),
      );
      expect(r.makingPaise, 706320);
    });

    test('is the default making method', () {
      expect(const JewelleryInput().makingMethod, MakingMethod.perGram);
    });
  });

  group('wastage (one method at a time)', () {
    test('percentage of gold value', () {
      final r = ok(
        base().copyWith(
          wastageMethod: WastageMethod.percent,
          wastagePercent: 8,
          wastageWeight: 99,
        ),
      );
      expect(r.wastagePaise, 424000); // 8% of 53,000 — weight ignored
    });

    test('wastage weight × gold rate', () {
      final r = ok(
        base().copyWith(
          wastageMethod: WastageMethod.weight,
          wastageWeight: 0.45,
          wastagePercent: 99,
        ),
      );
      expect(r.wastagePaise, 238500); // 0.45 g × 5300 — percent ignored
    });

    test('none ignores both values', () {
      final r = ok(base().copyWith(wastagePercent: 10, wastageWeight: 1));
      expect(r.wastagePaise, 0);
    });

    test('selected method requires its value', () {
      expect(
        engine
            .calculate(
              base().copyWith(wastageMethod: WastageMethod.percent),
              rates,
            )
            .issues
            .single
            .field,
        'wastagePercent',
      );
      expect(
        engine
            .calculate(
              base().copyWith(wastageMethod: WastageMethod.weight),
              rates,
            )
            .issues
            .single
            .field,
        'wastageWeight',
      );
    });
  });

  group('GST on configured taxable base', () {
    final input = JewelleryInput(
      purity: Purity.k22,
      goldWeight: 10,

      makingMethod: MakingMethod.fixed,
      makingValue: 5000,
      wastageMethod: WastageMethod.weight,
      wastageWeight: 0.2,
      gst: allTaxable3,
      stones: [dia(0.1, 50000)],
    );
    // gold 64,500; diamond 5,000; wastage 1,290; making 5,000 => 75,790

    test('all components taxable', () {
      final r = ok(input);
      expect(r.subtotalPaise, 7579000);
      expect(r.taxableBasePaise, 7579000);
      expect(r.gstPaise, 227370);
      expect(r.totalPaise, 7806370);
    });

    test('only selected components form the base', () {
      final r = ok(
        input.copyWith(
          gst: const GstConfig(
            ratePercent: 3,
            taxable: {PriceComponent.gold, PriceComponent.making},
          ),
        ),
      );
      expect(r.taxableBasePaise, 6950000);
      expect(r.gstPaise, 208500);
      expect(r.totalPaise, 7579000 + 208500);
    });

    test('separate GST rate for making charges', () {
      final r = ok(
        input.copyWith(
          gst: const GstConfig(ratePercent: 3, makingRatePercent: 5),
        ),
      );
      expect(r.gstLines, hasLength(2));
      expect(r.gstLines[0].basePaise, 7079000);
      expect(r.gstLines[0].amountPaise, 212370);
      expect(r.gstLines[1].basePaise, 500000);
      expect(r.gstLines[1].amountPaise, 25000);
      expect(r.taxableBasePaise, 7579000);
      expect(r.gstPaise, 237370);
    });

    test('no taxable components gives zero GST', () {
      final r = ok(
        input.copyWith(gst: const GstConfig(ratePercent: null, taxable: {})),
      );
      expect(r.gstPaise, 0);
      expect(r.totalPaise, r.subtotalPaise);
    });

    test('GST rounding to the paisa', () {
      final r = ok(
        base(goldWeight: 1.111, gst: const GstConfig(ratePercent: 3)),
      );
      // gold 5888.30 -> GST 176.649 -> 176.65
      expect(r.goldValuePaise, 588830);
      expect(r.gstPaise, 17665);
    });
  });

  group('multiple stone lines (e.g. DIA\\0.38\\700 tags)', () {
    test('each line priced at its own rate and summed by kind', () {
      final r = ok(
        base().copyWith(
          stones: const [
            StoneLine(
              kind: StoneKind.diamond,
              label: 'DIA',
              weightCt: 0.38,
              ratePerCt: 70000,
              code: '700',
            ),
            StoneLine(
              kind: StoneKind.diamond,
              label: 'DIA',
              weightCt: 0.11,
              ratePerCt: 75000,
              code: '750',
            ),
            StoneLine(
              kind: StoneKind.stone,
              label: 'FANCY CUT',
              weightCt: 2.13,
              ratePerCt: 8500,
              code: '850',
            ),
          ],
        ),
      );
      expect(r.stoneLinePaise, [2660000, 825000, 1810500]);
      expect(r.diamondValuePaise, 2660000 + 825000);
      expect(r.stoneValuePaise, 1810500);
    });

    test('a line missing its rate is reported against that line', () {
      final o = engine.calculate(
        base().copyWith(stones: [dia(0.38, 70000), dia(0.11, null)]),
        rates,
      );
      expect(o.issues.single.field, 'stone.1.rate');
    });

    test('excluding diamonds excludes every diamond line only', () {
      final r = ok(
        base().copyWith(
          excludeDiamond: true,
          stones: [dia(0.38, null), dia(0.11, 75000), stn(1, 1000)],
        ),
      );
      expect(r.diamondValuePaise, 0);
      expect(r.stoneValuePaise, 100000);
    });

    test('tag code is never used as a rate', () {
      final o = engine.calculate(
        base().copyWith(
          stones: const [
            StoneLine(kind: StoneKind.diamond, weightCt: 0.38, code: '700'),
          ],
        ),
        rates,
      );
      expect(o.issues.single.field, 'stone.0.rate');
    });
  });

  test('polki is priced like diamonds/stones but totalled separately', () {
    final r = ok(
      base().copyWith(
        stones: const [
          StoneLine(
            kind: StoneKind.diamond,
            weightCt: 0.25,
            ratePerCt: 70000,
            code: '700',
          ),
          StoneLine(
            kind: StoneKind.polki,
            label: 'POLKI',
            weightCt: 0.50,
            ratePerCt: 30000,
            code: '300',
          ),
          StoneLine(kind: StoneKind.stone, weightCt: 0.10, ratePerCt: 45000),
        ],
      ),
    );
    expect(r.diamondValuePaise, 1750000);
    expect(r.polkiValuePaise, 1500000);
    expect(r.stoneValuePaise, 450000);
    expect(r.componentPaise(PriceComponent.polki), 1500000);
    // Polki is taxable by default.
    expect(r.taxableBasePaise, r.subtotalPaise);
  });

  test('polki line without a rate is reported against that line', () {
    final o = engine.calculate(
      base().copyWith(
        stones: const [StoneLine(kind: StoneKind.polki, weightCt: 0.5)],
      ),
      rates,
    );
    expect(o.issues.single.field, 'stone.0.rate');
  });

  group('stones are priced per piece (× 1 or × 10)', () {
    test('pieces × rate', () {
      final r = ok(
        base().copyWith(
          stones: const [
            StoneLine(
              kind: StoneKind.stone,
              label: 'STN',
              weightCt: 4,
              ratePerCt: 600,
              code: '600',
            ),
          ],
        ),
      );
      expect(r.stoneValuePaise, 240000); // 4 × 600 = ₹2,400
    });

    test('pieces × rate × 10', () {
      final r = ok(
        base().copyWith(
          stones: const [
            StoneLine(
              kind: StoneKind.stone,
              weightCt: 4,
              ratePerCt: 600,
              rateFactor: 10,
            ),
          ],
        ),
      );
      expect(r.stoneValuePaise, 2400000); // 4 × 600 × 10 = ₹24,000
    });

    test('the ×10 factor never applies to diamonds or polki', () {
      final r = ok(
        base().copyWith(
          stones: const [
            StoneLine(
              kind: StoneKind.diamond,
              weightCt: 0.5,
              ratePerCt: 70000,
              rateFactor: 10,
            ),
          ],
        ),
      );
      expect(r.diamondValuePaise, 3500000);
    });

    test('factor survives JSON round-trip; old records default to ×1', () {
      const l = StoneLine(
        kind: StoneKind.stone,
        weightCt: 3,
        ratePerCt: 500,
        rateFactor: 10,
      );
      expect(StoneLine.fromJson(l.toJson()).rateFactor, 10);
      expect(
        StoneLine.fromJson({'kind': 'stone', 'weightCt': 3.0}).rateFactor,
        1,
      );
    });
  });

  test('line items always sum to totals', () {
    final r = ok(
      JewelleryInput(
        purity: Purity.k14,
        goldWeight: 2.333,

        makingMethod: MakingMethod.percentOfGold,
        makingValue: 13.33,
        wastageMethod: WastageMethod.percent,
        wastagePercent: 7.77,
        gst: const GstConfig(ratePercent: 3),
        stones: [dia(0.077, 41111), stn(0.033, 999.99)],
      ),
    );
    expect(
      r.goldValuePaise +
          r.diamondValuePaise +
          r.stoneValuePaise +
          r.wastagePaise +
          r.makingPaise,
      r.subtotalPaise,
    );
    expect(r.subtotalPaise + r.gstPaise, r.totalPaise);
  });

  test('result survives JSON round-trip', () {
    final r = ok(base(makingValue: 100).copyWith(stones: [dia(0.1, 1000)]));
    final back = PricingResult.fromJson(r.toJson());
    expect(back.totalPaise, r.totalPaise);
    expect(back.gstLines.single.basePaise, r.gstLines.single.basePaise);
  });
}
