import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/pricing/pricing_engine.dart';

const rates = {
  Purity.k14: 4100.0,
  Purity.k18: 5300.0,
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
          diamondWeight: 0.5,
          diamondRate: 30000,
          stoneWeight: 0.2,
          stoneRate: 5000,
          makingMethod: MakingMethod.percentOfGold,
          makingValue: 10,
          wastageMethod: WastageMethod.percent,
          wastagePercent: 5,
          gst: allTaxable3,
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
        base().copyWith(
          diamondWeight: -0.1,
          diamondRate: -5,
          stoneWeight: -1,
          stoneRate: -2,
          grossWeight: -3,
        ),
        rates,
      );
      expect(
        o.issues.map((i) => i.field).toSet(),
        containsAll([
          'diamondWeight',
          'diamondRate',
          'stoneWeight',
          'stoneRate',
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
      final r = ok(base().copyWith(diamondWeight: 0.37, diamondRate: 65000));
      expect(r.diamondValuePaise, 2405000);
    });

    test('stone value = ct × rate/ct', () {
      final r = ok(base().copyWith(stoneWeight: 1.25, stoneRate: 1200));
      expect(r.stoneValuePaise, 150000);
    });

    test('missing diamond rate blocks the calculation', () {
      final o = engine.calculate(base().copyWith(diamondWeight: 0.5), rates);
      expect(o.issues.single.field, 'diamondRate');
    });

    test('diamond can be explicitly excluded instead', () {
      final r = ok(base().copyWith(diamondWeight: 0.5, excludeDiamond: true));
      expect(r.diamondValuePaise, 0);
      expect(r.notes.join(), contains('excluded'));
    });

    test('missing stone rate blocks; zero stone rate is allowed', () {
      expect(
        engine
            .calculate(base().copyWith(stoneWeight: 0.2), rates)
            .issues
            .single
            .field,
        'stoneRate',
      );
      final r = ok(base().copyWith(stoneWeight: 0.2, stoneRate: 0));
      expect(r.stoneValuePaise, 0);
    });

    test('stone can be excluded', () {
      final r = ok(base().copyWith(stoneWeight: 0.2, excludeStone: true));
      expect(r.stoneValuePaise, 0);
    });

    test('rate without weight contributes nothing', () {
      final r = ok(base().copyWith(diamondRate: 50000));
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
      diamondWeight: 0.1,
      diamondRate: 50000,
      makingValue: 5000,
      wastageMethod: WastageMethod.weight,
      wastageWeight: 0.2,
      gst: allTaxable3,
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

  test('line items always sum to totals', () {
    final r = ok(
      JewelleryInput(
        purity: Purity.k14,
        goldWeight: 2.333,
        diamondWeight: 0.077,
        diamondRate: 41111,
        stoneWeight: 0.033,
        stoneRate: 999.99,
        makingMethod: MakingMethod.percentOfGold,
        makingValue: 13.33,
        wastageMethod: WastageMethod.percent,
        wastagePercent: 7.77,
        gst: const GstConfig(ratePercent: 3),
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
    final r = ok(
      base(makingValue: 100).copyWith(diamondWeight: 0.1, diamondRate: 1000),
    );
    final back = PricingResult.fromJson(r.toJson());
    expect(back.totalPaise, r.totalPaise);
    expect(back.gstLines.single.basePaise, r.gstLines.single.basePaise);
  });
}
