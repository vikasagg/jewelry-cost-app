import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/ocr/tag_parser.dart';

String sample(String name) => File('samples/tags/$name').readAsStringSync();

void main() {
  const parser = TagParser();

  group('purity recognition', () {
    final cases = {
      '18KT': Purity.k18,
      'Purity: 14K': Purity.k14,
      'GOLD 22 KARAT': Purity.k22,
      '24k coin': Purity.k24,
      '22K916': Purity.k22,
      '18 K': Purity.k18,
      'kt: 14': Purity.k14,
    };
    cases.forEach((text, purity) {
      test('"$text" -> ${purity.label}', () {
        final p = parser.parse(text).purity;
        expect(p.value, purity);
        expect(p.confidence, FieldConfidence.high);
      });
    });

    test('hallmark fineness alone is flagged for confirmation', () {
      for (final e in {
        '750': Purity.k18,
        '916': Purity.k22,
        '585': Purity.k14,
        '999': Purity.k24,
      }.entries) {
        final p = parser.parse('Ring\n${e.key}').purity;
        expect(p.value, e.value);
        expect(p.confidence, FieldConfidence.low);
        expect(p.note, contains('fineness'));
      }
    });

    test('conflicting purities are flagged', () {
      final p = parser.parse('18K\nGW 5.0 g\n22K').purity;
      expect(p.confidence, FieldConfidence.low);
    });

    test('missing purity is missing, not guessed', () {
      final t = parser.parse('GW 5.000 g');
      expect(t.purity.confidence, FieldConfidence.missing);
      expect(t.missingRequired, contains('purity'));
    });

    test('a tag number containing 750 is not read as purity', () {
      final t = parser.parse('Tag No: 750123\nGW 2.0 g');
      expect(t.purity.isFound, isFalse);
      expect(t.tagNumber.value, '750123');
    });
  });

  group('weights', () {
    test('label variants for gold weight', () {
      for (final s in [
        'GW 10.250',
        'G.W. 10.250 g',
        'Gold Wt: 10.250gm',
        'GOLD WEIGHT - 10.250',
        'Gross Gold Weight 10.250 grams',
        'g.w 10.250',
        'G W: 10.250 G',
      ]) {
        final w = parser.parse(s).goldWeight;
        expect(w.value, 10.25, reason: s);
        expect(w.confidence, FieldConfidence.high, reason: s);
      }
    });

    test('diamond & stone weights in carats', () {
      final t = parser.parse('DW 0.50 ct\nStone Wt: 0.20 cts\nGW 3.1 g');
      expect(t.diamondWeight.value, 0.5);
      expect(t.stoneWeight.value, 0.2);
      expect(t.goldWeight.value, 3.1);
      expect(t.diamondWeight.confidence, FieldConfidence.high);
    });

    test('leading-decimal values like ".35" are read correctly', () {
      expect(parser.parse('S.W. .35 ct').stoneWeight.value, 0.35);
    });

    test('value on the line after its label', () {
      expect(parser.parse('GOLD WT\n4.560').goldWeight.value, 4.56);
    });

    test('missing gold weight is reported, not guessed', () {
      final t = parser.parse(sample('07_missing_gold.txt'));
      expect(t.goldWeight.isFound, isFalse);
      expect(t.missingRequired, contains('goldWeight'));
      expect(t.diamondWeight.value, 0.22);
    });

    test('unreadable characters are substituted but flagged', () {
      final w = parser.parse('GW 1O.5O g').goldWeight;
      expect(w.value, 10.5);
      expect(w.confidence, FieldConfidence.low);
      expect(w.note, isNotNull);
    });

    test('comma decimals are flagged', () {
      final w = parser.parse('GW 10,250 g').goldWeight;
      expect(w.value, 10.25);
      expect(w.confidence, FieldConfidence.low);
    });

    test('implausible weight (missing decimal) is flagged', () {
      final w = parser.parse('GW 10250 g').goldWeight;
      expect(w.confidence, FieldConfidence.low);
    });

    test('carat unit on gold weight is flagged', () {
      expect(
        parser.parse('GW 2.5 ct').goldWeight.confidence,
        FieldConfidence.low,
      );
    });

    test(
      'GW together with NW: NW is gold, GW is gross, both need confirmation',
      () {
        final t = parser.parse(sample('06_gross_and_net.txt'));
        expect(t.goldWeight.value, 5.92);
        expect(t.grossWeight.value, 6.40);
        expect(t.goldWeight.confidence, FieldConfidence.low);
        expect(t.grossWeight.confidence, FieldConfidence.low);
      },
    );

    test('gross weight is kept separate from gold weight', () {
      final t = parser.parse('Gross Wt 7.10 g\nGold Wt 6.55 g\nDW 0.40 ct');
      expect(t.grossWeight.value, 7.10);
      expect(t.goldWeight.value, 6.55); // never gross − stones
    });
  });

  group('making & wastage', () {
    test('fixed making with rupee symbol and thousands separator', () {
      final t = parser.parse('MC: ₹ 7,000');
      expect(t.makingMethod.value, MakingMethod.fixed);
      expect(t.makingValue.value, 7000);
      expect(t.makingValue.confidence, FieldConfidence.high);
    });

    test('percentage making', () {
      final t = parser.parse('Making Charges 12.5%');
      expect(t.makingMethod.value, MakingMethod.percentOfGold);
      expect(t.makingValue.value, 12.5);
    });

    test('per-gram making is flagged', () {
      final t = parser.parse('MC 450/g');
      expect(t.makingMethod.confidence, FieldConfidence.low);
    });

    test('wastage percent vs weight', () {
      expect(
        parser.parse('Wastage 8%').wastageMethod.value,
        WastageMethod.percent,
      );
      final w = parser.parse('VA 0.45 g');
      expect(w.wastageMethod.value, WastageMethod.weight);
      expect(w.wastageValue.value, 0.45);
      final u = parser.parse('Wastage 6');
      expect(u.wastageMethod.confidence, FieldConfidence.low);
    });
  });

  group('sample tags', () {
    test('01 diamond ring 18K', () {
      final t = parser.parse(sample('01_diamond_ring_18k.txt'));
      expect(t.itemName.value, 'Diamond Ring');
      expect(t.tagNumber.value, 'DR-18-0425');
      expect(t.purity.value, Purity.k18);
      expect(t.goldWeight.value, 10.25);
      expect(t.diamondWeight.value, 0.5);
      expect(t.stoneWeight.value, 0.2);
      expect(t.makingValue.value, 7000);
      expect(t.uncertainFields, isEmpty);
    });

    test('02 bangle 22K', () {
      final t = parser.parse(sample('02_bangle_22k.txt'));
      expect(t.itemName.value, 'Plain Bangle');
      expect(t.tagNumber.value, 'B22-1187');
      expect(t.purity.value, Purity.k22);
      expect(t.goldWeight.value, 24.68);
      expect(t.makingMethod.value, MakingMethod.percentOfGold);
      expect(t.makingValue.value, 12);
      expect(t.wastageMethod.value, WastageMethod.percent);
      expect(t.wastageValue.value, 8);
      expect(t.diamondWeight.isFound, isFalse);
    });

    test('03 pendant 14K (lower-case, abbreviations)', () {
      final t = parser.parse(sample('03_pendant_14k.txt'));
      expect(t.purity.value, Purity.k14);
      expect(t.tagNumber.value, 'P14-302');
      expect(t.goldWeight.value, 3.12);
      expect(t.diamondWeight.value, 0.12);
      expect(t.stoneWeight.value, 0.35);
      expect(t.makingValue.value, 1500);
    });

    test('04 coin 24K (value on next line)', () {
      final t = parser.parse(sample('04_coin_24k.txt'));
      expect(t.purity.value, Purity.k24);
      expect(t.goldWeight.value, 10.0);
      expect(t.tagNumber.value, 'C24-10G');
    });

    test('05 noisy OCR chain', () {
      final t = parser.parse(sample('05_ocr_noise_chain.txt'));
      expect(t.purity.value, Purity.k22);
      expect(t.goldWeight.value, 10.5);
      expect(t.uncertainFields.keys, contains('goldWeight'));
      expect(t.wastageMethod.value, WastageMethod.weight);
      expect(t.wastageValue.value, 0.45);
    });

    test('real Tesseract output of sample 05 (stray symbols, blank lines)', () {
      // Captured from the web build scanning samples/tags/05_ocr_noise_chain.png.
      const ocr =
          'Item: Chain\n\nTag No: CH-0091\nPurity: 22K O\nGW 10.50 ¢g\n\nVA 0.45 ¢g\n';
      final t = parser.parse(ocr);
      expect(t.tagNumber.value, 'CH-0091');
      expect(t.itemName.value, 'Chain');
      expect(t.purity.value, Purity.k22);
      expect(t.goldWeight.value, 10.5);
      expect(t.wastageMethod.value, WastageMethod.weight);
      expect(t.wastageValue.value, 0.45);
      expect(t.uncertainFields, isEmpty);
    });

    test('toInput keeps defaults for fields not on the tag', () {
      final t = parser.parse(sample('01_diamond_ring_18k.txt'));
      final input = t.toInput(
        const JewelleryInput(
          diamondRate: 30000,
          gst: GstConfig(ratePercent: 3),
        ),
      );
      expect(input.diamondRate, 30000);
      expect(input.gst.ratePercent, 3);
      expect(input.goldWeight, 10.25);
    });
  });
}
