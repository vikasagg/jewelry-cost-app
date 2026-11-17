import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/main.dart';
import 'package:jewellery_cost/metals/metal_prices.dart';
import 'package:jewellery_cost/models/purity.dart';

void main() {
  test('prices per day, latest and share text', () async {
    var now = DateTime(2026, 11, 4, 10);
    final book = MetalPriceBook(MemoryStore(), clock: () => now);
    expect(book.byDate(book.today), isNull);
    await book.save('2026-11-04', gold24Per10g: 129500, silverPerKg: 158000);
    now = DateTime(2026, 11, 5, 10);
    final p = await book.save('2026-11-05', gold24Per10g: 130000);
    expect(book.all().map((e) => e.date), ['2026-11-05', '2026-11-04']);
    expect(book.before('2026-11-05')!.gold24Per10g, 129500);
    expect(book.latest.silverPerKg, 158000); // from the day before
    expect(p.goldPer10g(Purity.k22), 119600);
    final text = metalPriceText(
      MetalPrice(
        date: '2026-11-05',
        gold24Per10g: 130000,
        silverPerKg: 160000,
        updatedAt: now,
      ),
    );
    expect(text, contains('Gold 24K: ₹1,30,000 / 10 g'));
    expect(text, contains('Gold 22K: ₹1,19,600 / 10 g'));
    expect(text, contains('Silver: ₹1,60,000 / kg'));
  });

  testWidgets('Home → Gold & Silver: record prices, calculator follows', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(
      MemoryStore(),
      clock: () => DateTime(2026, 11, 5, 10),
    );
    await state.metalPrices.save(
      '2026-11-04',
      gold24Per10g: 129500,
      silverPerKg: 158000,
    );
    await t.pumpWidget(JewelleryCostApp(state: state));
    expect(find.text("Record today's prices"), findsOneWidget);
    await t.tap(find.byKey(const Key('openMetalPrices')));
    await t.pumpAndSettle();

    // Silver is filled in from the last record.
    expect(find.text('158000'), findsOneWidget);
    await t.enterText(find.byKey(const Key('gold24Field')), '130000');
    await t.enterText(find.byKey(const Key('silverField')), '160000');
    await t.pump();
    expect(find.text('₹1,19,600 / 10 g'), findsOneWidget); // 22K
    expect(find.text('₹1,600'), findsOneWidget); // silver per 10 g
    await t.tap(find.byKey(const Key('saveMetalPrices')));
    await t.pumpAndSettle();

    final p = state.metalPrices.byDate('2026-11-05')!;
    expect(p.gold24Per10g, 130000);
    expect(p.silverPerKg, 160000);
    // The Price Calculator now uses it (₹13,000 per gram of 24K).
    expect(state.rates!.perGram[Purity.k24], 13000);
    expect(state.rates!.quotedPerGrams, 10);
    // History shows the rise from yesterday.
    expect(find.text(' ▲ ₹500'), findsOneWidget);
    expect(find.text(' ▲ ₹2,000'), findsOneWidget);

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Gold ₹1,30,000 · Silver ₹1,60,000/kg'), findsOneWidget);
  });
}
