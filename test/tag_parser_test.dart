import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/ocr/tag_parser.dart';

String sample(String name) => File('samples/tags/$name').readAsStringSync();

ParsedStone dia(ParsedTag t) =>
    t.stones.firstWhere((s) => s.kind.value == StoneKind.diamond);
ParsedStone stn(ParsedTag t) =>
    t.stones.firstWhere((s) => s.kind.value == StoneKind.stone);

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
      '9K': Purity.k9,
      'Purity: 9KT': Purity.k9,
      '20K': Purity.k20,
      '20 KT 833': Purity.k20,
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
        '833': Purity.k20,
        '375': Purity.k9,
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
      expect(dia(t).weight.value, 0.5);
      expect(stn(t).weight.value, 0.2);
      expect(t.goldWeight.value, 3.1);
      expect(dia(t).weight.confidence, FieldConfidence.high);
    });

    test('leading-decimal values like ".35" are read correctly', () {
      expect(stn(parser.parse('S.W. .35 ct')).weight.value, 0.35);
    });

    test('value on the line after its label', () {
      expect(parser.parse('GOLD WT\n4.560').goldWeight.value, 4.56);
    });

    test('missing gold weight is reported, not guessed', () {
      final t = parser.parse(sample('07_missing_gold.txt'));
      expect(t.goldWeight.isFound, isFalse);
      expect(t.missingRequired, contains('goldWeight'));
      expect(dia(t).weight.value, 0.22);
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
      // Shop rule: a bare making charge is per gram.
      expect(t.makingMethod.value, MakingMethod.perGram);
      expect(t.makingValue.value, 7000);
      expect(t.makingValue.confidence, FieldConfidence.high);
    });

    test('percentage making', () {
      final t = parser.parse('Making Charges 12.5%');
      expect(t.makingMethod.value, MakingMethod.percentOfGold);
      expect(t.makingValue.value, 12.5);
    });

    test('per-gram making ("1200/g") is read as per gram', () {
      final t = parser.parse('MC 1200/g');
      expect(t.makingMethod.value, MakingMethod.perGram);
      expect(t.makingMethod.confidence, FieldConfidence.high);
      expect(t.makingValue.value, 1200);
    });

    test('"/-" marks a fixed total amount', () {
      final t = parser.parse('mc 1500/-');
      expect(t.makingMethod.value, MakingMethod.fixed);
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

  group('real tag: G.Wt / N.Wt / DIA\\weight\\code lines (08)', () {
    void expectStones(ParsedTag t) {
      expect(t.stones.map((s) => s.label), ['DIA', 'DIA', 'FANCY CUT']);
      expect(t.stones.map((s) => s.weight.value), [0.38, 0.11, 2.13]);
      expect(t.stones.map((s) => s.code), ['700', '750', '850']);
    }

    test('clean text', () {
      final t = parser.parse(sample('08_real_14k_diamond.txt'));
      expect(t.purity.value, Purity.k14);
      expect(t.goldWeight.value, 5.886); // N.Wt is the gold weight
      expect(t.grossWeight.value, 6.410);
      expectStones(t);
      // 6.410 − 5.886 = 0.524 g = 2.62 ct = 0.38 + 0.11 + 2.13
      expect(t.weightBalance!.balances, isTrue);
      expect(t.goldWeight.confidence, FieldConfidence.high);
      expect(t.grossWeight.confidence, FieldConfidence.high);
      expect(t.stones.every((s) => s.kind.value == StoneKind.diamond), isTrue);
      expect(t.uncertainFields, isEmpty);
    });

    // Actual Tesseract output for the photo after crop + rotate.
    test('OCR: backslash lost before code ("2.13850")', () {
      final t = parser.parse(
        'RO AAAS LICORICE ECE pg ~~)\nJ G.Wt :6.410 14K\n7 N.Wt:5.886\n'
        '_ DIA\\0.38\\700\n~ DIA\\0.11\\750\nCS ENEANCY CUT) 2.13850\n',
      );
      expect(t.purity.value, Purity.k14);
      expect(t.goldWeight.value, 5.886);
      expectStones(t);
      // The 2.13 / 850 split is confirmed by the weight balance.
      expect(t.stones[2].weight.confidence, FieldConfidence.high);
      expect(t.uncertainFields, isEmpty);
    });

    test('OCR: backslash read as N and as 1 ("DIAN0.11", "2.131850")', () {
      final t = parser.parse(
        '3 G.Wt :6.410 14K\n7 N.Wt:5.886\n_ DIA\\0.38\\700\n'
        '. DIAN0.11\\750\nEna ANCY CUT) 2.131850\n',
      );
      expectStones(t);
      expect(t.weightBalance!.balances, isTrue);
    });

    test('OCR via the web app (crop + auto-rotate): stray "|", "~#N"', () {
      final t = parser.parse(
        '4 G.Wt :6.410 14K :\n© N.Wt:5.886 :\n\'  DIA\\0.38\\700 |\n'
        '| DIA\\0.11\\750\n~#NEANCY CUT) 2.13\\850 |\n',
      );
      expect(t.purity.value, Purity.k14);
      expect(t.goldWeight.value, 5.886);
      expect(t.grossWeight.value, 6.410);
      expectStones(t);
      expect(t.uncertainFields, isEmpty);
    });

    test(
      'OCR: G.Wt label lost → no balance, unclear split must be confirmed',
      () {
        final t = parser.parse(
          'Eat 16.410 14K\nN.Wt :5.886\n. DIA\\0.38\\700\nDIA\\0.11\\750\n'
          'S@ANCY CUT\\ 2.131850\n',
        );
        expect(t.goldWeight.value, 5.886);
        expect(t.goldWeight.confidence, FieldConfidence.high);
        expect(t.grossWeight.isFound, isFalse); // never guessed from "16.410"
        expectStones(t);
        expect(t.uncertainFields.keys, ['stone.2.weight']);
      },
    );

    test('weights that do not balance are flagged', () {
      final t = parser.parse(
        'G.Wt :6.410 14K\nN.Wt :5.886\nDIA\\0.38\\700\nDIA\\0.11\\750\n',
      );
      expect(t.weightBalance!.balances, isFalse);
      expect(
        t.uncertainFields.keys,
        containsAll(['goldWeight', 'grossWeight', 'stone.0.weight']),
      );
    });

    test('rotation scoring prefers the upright reading', () {
      // Unrotated photo: Tesseract returns noise.
      final sideways = parser.parse(
        'SOILY LAT oh Ded BS 7\nGEN AN A Te . 4 Fo Sal',
      );
      final upright = parser.parse(sample('08_real_14k_diamond.txt'));
      expect(scoreParsedTag(upright), greaterThan(scoreParsedTag(sideways)));
      expect(scoreParsedTag(sideways), 0);
    });

    test('stone weight implied by G.Wt − N.Wt but no stone lines read', () {
      final t = parser.parse('G.Wt :6.410 14K\nN.Wt :5.886\nnoise noise');
      expect(t.unreadStoneWeightG, closeTo(0.524, 1e-9));
      expect(
        parser.parse(sample('08_real_14k_diamond.txt')).unreadStoneWeightG,
        isNull,
      );
    });

    test('codes 700/750/850 are never read as hallmark purity', () {
      final t = parser.parse('N.Wt :5.886\nDIA\\0.38\\750\n');
      expect(t.purity.isFound, isFalse);
    });

    test('remembered per-code rates are applied, unknown codes left empty', () {
      final t = parser.parse(sample('08_real_14k_diamond.txt'));
      final input = t.toInput(
        const JewelleryInput(),
        rateFor: (kind, code) => code == '700' ? 70000 : null,
      );
      expect(input.stones.map((s) => s.ratePerCt), [70000, null, null]);
    });
  });

  group('Stn lines (weight\\code like DIA)', () {
    test('Stn\\0.25\\600 and Stn/0.10/450 → stone lines with codes', () {
      final t = parser.parse(
        'N.Wt :3.250 18K\nDIA\\0.12\\700\nStn\\0.25\\600\nStn/0.10/450\n',
      );
      expect(t.stones.map((s) => s.label), ['DIA', 'STN', 'STN']);
      expect(t.stones.map((s) => s.kind.value), [
        StoneKind.diamond,
        StoneKind.stone,
        StoneKind.stone,
      ]);
      expect(t.stones.map((s) => s.weight.value), [0.12, 0.25, 0.10]);
      expect(t.stones.map((s) => s.code), ['700', '600', '450']);
      final input = t.toInput(
        const JewelleryInput(),
        rateFor: (kind, code) => double.parse(code!) * 100,
      );
      expect(input.stones[1].ratePerCt, 60000);
      expect(input.stones[2].ratePerCt, 45000);
    });

    test('stone pieces are not used in the gross − net weight balance', () {
      // 6.410 − 5.886 = 0.524 g; the stone line is 4 pieces of unknown weight.
      final t = parser.parse(
        'G.Wt :6.410 14K\nN.Wt :5.886\nDIA\\0.49\\700\nStn\\4\\600\n',
      );
      expect(t.weightBalance, isNull);
      expect(t.stones.last.weight.value, 4);
      expect(t.uncertainFields.keys, isNot(contains('stone.0.weight')));
      expect(t.uncertainFields.keys, isNot(contains('stone.1.weight')));
    });

    test('Stn.M is treated as Stn', () {
      final t = parser.parse('Stn.M\\0.40\\350\nSTN.M/0.05/300');
      expect(t.stones.map((s) => s.label), ['STN', 'STN']);
      expect(t.stones.map((s) => s.weight.value), [0.40, 0.05]);
      expect(t.stones.map((s) => s.code), ['350', '300']);
      expect(t.stones.every((s) => s.kind.value == StoneKind.stone), isTrue);
    });

    test('wastage printed on a tag is ignored', () {
      final t = parser.parse('N.Wt 2.000 22K\nWastage 8%');
      expect(t.uncertainFields, isEmpty);
      expect(
        t.toInput(const JewelleryInput()).wastageMethod,
        WastageMethod.none,
      );
    });
  });

  group('Polki lines', () {
    test('Polki\\0.50\\300 is its own kind with a tag rate code', () {
      final t = parser.parse(
        'G.Wt :8.100 22K\nN.Wt :7.900\nDIA\\0.25\\700\nPolki\\0.50\\300\nPOLKI/0.25/250\n',
      );
      expect(t.stones.map((s) => s.label), ['DIA', 'POLKI', 'POLKI']);
      expect(t.stones.map((s) => s.kind.value), [
        StoneKind.diamond,
        StoneKind.polki,
        StoneKind.polki,
      ]);
      expect(t.stones.map((s) => s.weight.value), [0.25, 0.50, 0.25]);
      expect(t.stones.map((s) => s.code), ['700', '300', '250']);
      // 8.100 − 7.900 = 0.200 g = 1.00 ct = 0.25 + 0.50 + 0.25
      expect(t.weightBalance!.balances, isTrue);
      expect(t.uncertainFields, isEmpty);
    });
  });

  group('sample tags', () {
    test('01 diamond ring 18K', () {
      final t = parser.parse(sample('01_diamond_ring_18k.txt'));
      expect(t.itemName.value, 'Diamond Ring');
      expect(t.tagNumber.value, 'DR-18-0425');
      expect(t.purity.value, Purity.k18);
      expect(t.goldWeight.value, 10.25);
      expect(dia(t).weight.value, 0.5);
      expect(stn(t).weight.value, 0.2);
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
      expect(t.stones, isEmpty);
    });

    test('03 pendant 14K (lower-case, abbreviations)', () {
      final t = parser.parse(sample('03_pendant_14k.txt'));
      expect(t.purity.value, Purity.k14);
      expect(t.tagNumber.value, 'P14-302');
      expect(t.goldWeight.value, 3.12);
      expect(dia(t).weight.value, 0.12);
      expect(stn(t).weight.value, 0.35);
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
        const JewelleryInput(gst: GstConfig(ratePercent: 3)),
        rateFor: (kind, code) => kind == StoneKind.diamond ? 30000 : null,
      );
      expect(input.stones.first.ratePerCt, 30000);
      expect(input.stones.first.weightCt, 0.5);
      expect(input.gst.ratePercent, 3);
      expect(input.goldWeight, 10.25);
    });
  });

  group('PaddleOCR output of the real tag photo', () {
    for (final text in [
      'G.Wt:6.410 14K\nN.Wt:5.886\nDIA0.38700\nDIA0.11750\nFANCY CUT\\2.13850',
      'G.Wt:6.410 14K\nN.Wt:5.886\nDIA0.38700\nDIA0.11750\nFANCY CUT2.13 850',
      'G.Wt:6.41014K\nN.Wt:5.886\nDIA0.38700\nDIA\\0.11750\nFANCY CUT\\2.13850',
    ]) {
      test(text.replaceAll('\n', ' | '), () {
        final t = parser.parse(text);
        expect(t.purity.value, Purity.k14);
        expect(t.goldWeight.value, 5.886);
        expect(t.grossWeight.value, 6.41);
        expect(
          [for (final s in t.stones) (s.weight.value, s.code)],
          [(0.38, '700'), (0.11, '750'), (2.13, '850')],
        );
        expect(t.uncertainFields, isEmpty);
      });
    }
  });

  group('labour (LBR) and a second photo', () {
    test('LBR is read as labour / making charges', () {
      for (final e in {
        'LBR : 1200': (MakingMethod.perGram, 1200.0),
        'LBR\\1500': (MakingMethod.perGram, 1500.0),
        'L.B.R. 12%': (MakingMethod.percentOfGold, 12.0),
        'LBR 15000/-': (MakingMethod.fixed, 15000.0),
      }.entries) {
        final t = parser.parse(e.key);
        expect(
          (t.makingMethod.value, t.makingValue.value),
          e.value,
          reason: e.key,
        );
      }
    });

    test('real labour-side tag: "Lbr.16.00%" and item code CH1619', () {
      final t = parser.parse('DJ\nCH1619\nCHAIN\nLbr.16.00%');
      expect(t.makingMethod.value, MakingMethod.percentOfGold);
      expect(t.makingValue.value, 16);
      expect(t.tagNumber.value, 'CH1619');
      expect(parser.parse('LBR 11.5%').makingValue.value, 11.5);
    });

    test('second photo fills only what the first one lacks', () {
      final front = parser
          .parse('G.Wt:6.410 14K\nN.Wt:5.886\nDIA\\0.38\\700')
          .confirm('goldWeight', 5.9);
      final back = parser.parse('Tag No: R-77\nLBR : 1200\nN.Wt 9.999');
      final m = front.mergeWith(back);
      expect(m.goldWeight.value, 5.9); // first photo (as confirmed) wins
      expect(m.purity.value, Purity.k14);
      expect(m.stones, hasLength(1));
      expect(m.makingValue.value, 1200);
      expect(m.makingMethod.value, MakingMethod.perGram);
      expect(m.tagNumber.value, 'R-77');
      expect(m.rawText, contains('2nd photo'));
    });
  });
}
