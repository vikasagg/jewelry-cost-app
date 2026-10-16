import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/ocr/tag_parser.dart';

StoneLine dia(double? w, double? r) =>
    StoneLine(kind: StoneKind.diamond, label: 'DIA', weightCt: w, ratePerCt: r);
StoneLine stn(double? w, double? r) =>
    StoneLine(kind: StoneKind.stone, label: 'Stone', weightCt: w, ratePerCt: r);

void main() {
  final day1 = DateTime(2026, 10, 1, 10, 30);
  final day2 = DateTime(2026, 10, 2, 11, 0);

  GoldRates ratesAt(double r18, DateTime t) => GoldRates(
    perGram: {
      Purity.k14: 4100,
      Purity.k18: r18,
      Purity.k22: 6450,
      Purity.k24: 7000,
    },
    updatedAt: t,
  );

  final input = JewelleryInput(
    tagNumber: 'DR-18-0425',
    itemName: 'Diamond Ring',
    purity: Purity.k18,
    goldWeight: 10,

    makingValue: 7000,
    gst: const GstConfig(ratePercent: 3),
    stones: [dia(0.5, 30000)],
  );

  test('gold rates persist between sessions', () async {
    final store = MemoryStore();
    final s1 = AppState(store);
    expect(s1.hasRates, isFalse);
    await s1.saveRates(ratesAt(5300, day1));
    final s2 = AppState(store);
    expect(s2.hasRates, isTrue);
    expect(s2.rates!.rateFor(Purity.k18), 5300);
    expect(s2.rates!.updatedAt, day1);
  });

  test('changing gold rates does not alter historical calculations', () async {
    final store = MemoryStore();
    var now = day1;
    final state = AppState(store, clock: () => now);
    await state.saveRates(ratesAt(5300, day1));

    final r1 = state.engine.calculate(input, state.rates!.perGram).result!;
    final saved = await state.saveCalculation(
      input: input,
      ratesSnapshot: state.rates!,
      result: r1,
    );

    now = day2;
    await state.saveRates(ratesAt(6000, day2));

    final reloaded = AppState(store).history.byId(saved.id)!;
    expect(reloaded.goldRateUsed, 5300);
    expect(reloaded.ratesSnapshot.rateFor(Purity.k18), 5300);
    expect(reloaded.ratesSnapshot.updatedAt, day1);
    expect(reloaded.result.totalPaise, r1.totalPaise);

    // Recomputing from the stored snapshot reproduces the stored result.
    final again = state.engine
        .calculate(reloaded.input, reloaded.ratesSnapshot.perGram)
        .result!;
    expect(again.totalPaise, r1.totalPaise);
    // With current rates it differs.
    final current = state.engine
        .calculate(reloaded.input, state.rates!.perGram)
        .result!;
    expect(current.totalPaise, isNot(r1.totalPaise));
  });

  test('edit, search and delete history', () async {
    final store = MemoryStore();
    var now = day1;
    final state = AppState(store, clock: () => now);
    await state.saveRates(ratesAt(5300, day1));
    final r = state.engine.calculate(input, state.rates!.perGram).result!;
    final a = await state.saveCalculation(
      input: input,
      ratesSnapshot: state.rates!,
      result: r,
    );
    now = day2;
    final other = input.copyWith(
      tagNumber: 'B22-1187',
      itemName: 'Bangle',
      purity: Purity.k22,
    );
    final r2 = state.engine.calculate(other, state.rates!.perGram).result!;
    await state.saveCalculation(
      input: other,
      ratesSnapshot: state.rates!,
      result: r2,
    );

    expect(state.history.all().first.input.tagNumber, 'B22-1187');
    expect(state.history.search('ring').single.id, a.id);
    expect(state.history.search('b22').single.input.itemName, 'Bangle');
    expect(state.history.search('').length, 2);

    final edited = input.copyWith(goldWeight: 11);
    final r3 = state.engine.calculate(edited, a.ratesSnapshot.perGram).result!;
    final updated = await state.saveCalculation(
      input: edited,
      ratesSnapshot: a.ratesSnapshot,
      result: r3,
      existingId: a.id,
    );
    expect(updated.id, a.id);
    expect(updated.createdAt, day1);
    expect(updated.updatedAt, day2);
    expect(state.history.all().length, 2);
    expect(state.history.byId(a.id)!.input.goldWeight, 11);

    await state.deleteCalculation(a.id);
    expect(state.history.all().length, 1);
  });

  test(
    'tag rate code × 100 = ₹ per carat; multiplier is configurable',
    () async {
      final store = MemoryStore();
      final state = AppState(store);
      expect(state.tagRateMultiplier, 100);
      expect(state.stoneRateFor(StoneKind.diamond, '700'), 70000);
      expect(state.stoneRateFor(StoneKind.diamond, '750'), 75000);
      expect(state.stoneRateFor(StoneKind.diamond, '850'), 85000);
      expect(state.stoneRateFor(StoneKind.diamond, 'AB'), isNull);
      await state.setTagRateMultiplier(1000);
      expect(AppState(store).stoneRateFor(StoneKind.diamond, '70'), 70000);
    },
  );

  test('real tag 08 prices end to end with tag rates', () async {
    final state = AppState(MemoryStore());
    await state.saveRates(ratesAt(5300, day1)); // 14K = ₹4,100/g
    final parsed = const TagParser().parse(
      File('samples/tags/08_real_14k_diamond.txt').readAsStringSync(),
    );
    final input = parsed
        .toInput(state.pricingDefaults, rateFor: state.stoneRateFor)
        .copyWith(makingValue: 0, gst: const GstConfig(ratePercent: 3));
    expect(input.stones.map((s) => s.ratePerCt), [70000, 75000, 85000]);
    final r = state.engine.calculate(input, state.rates!.perGram).result!;
    expect(r.goldValuePaise, 2413260); // 5.886 g × ₹4,100
    expect(r.stoneLinePaise, [2660000, 825000, 18105000]);
    expect(r.diamondValuePaise, 2660000 + 825000 + 18105000);
    expect(r.subtotalPaise, 2413260 + 21590000);
  });

  test('records saved before multi-line stones still load', () {
    final old = JewelleryInput.fromJson({
      'purity': 'k18',
      'goldWeight': 10.0,
      'diamondWeight': 0.5,
      'diamondRate': 30000.0,
      'stoneWeight': 0.2,
      'stoneRate': 5000.0,
      'makingValue': 0.0,
    });
    expect(old.stones, hasLength(2));
    expect(old.diamondWeight, 0.5);
    expect(old.stones.last.kind, StoneKind.stone);
    expect(old.stones.last.ratePerCt, 5000);
  });

  test('every new item starts clean: GST 3%, nothing carried over', () async {
    final state = AppState(MemoryStore());
    await state.saveRates(ratesAt(5300, day1));
    final previous = input.copyWith(
      makingMethod: MakingMethod.perGram,
      makingValue: 1200,
      gst: const GstConfig(ratePercent: 5),
    );
    final r = state.engine.calculate(previous, state.rates!.perGram).result!;
    await state.saveCalculation(
      input: previous,
      ratesSnapshot: state.rates!,
      result: r,
    );
    final d = state.pricingDefaults;
    expect(d.gst.ratePercent, 3);
    expect(d.makingMethod, MakingMethod.perGram);
    expect(d.makingValue, isNull);
    expect(
      d.stones.every((s) => s.ratePerCt == null && s.weightCt == null),
      isTrue,
    );
    expect(d.wastageMethod, WastageMethod.none);
    expect(d.goldWeight, isNull);
    expect(d.tagNumber, isNull);
  });
}
