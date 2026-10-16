import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';

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

  const input = JewelleryInput(
    tagNumber: 'DR-18-0425',
    itemName: 'Diamond Ring',
    purity: Purity.k18,
    goldWeight: 10,
    diamondWeight: 0.5,
    diamondRate: 30000,
    makingValue: 7000,
    gst: GstConfig(ratePercent: 3),
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

  test('pricing defaults remember rates and GST but not item data', () async {
    final state = AppState(MemoryStore());
    await state.saveRates(ratesAt(5300, day1));
    final r = state.engine.calculate(input, state.rates!.perGram).result!;
    await state.saveCalculation(
      input: input,
      ratesSnapshot: state.rates!,
      result: r,
    );
    final d = state.pricingDefaults;
    expect(d.diamondRate, 30000);
    expect(d.gst.ratePercent, 3);
    expect(d.goldWeight, isNull);
    expect(d.tagNumber, isNull);
  });
}
