import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/main.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/ocr/tag_parser.dart';
import 'package:jewellery_cost/ui/screens/details_form_screen.dart';
import 'package:jewellery_cost/ui/theme.dart';

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final list = [
      'resultList',
      'formList',
    ].map((k) => find.byKey(Key(k))).firstWhere((l) => l.evaluate().isNotEmpty);
    for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
      await t.drag(list, const Offset(0, -250));
      await t.pumpAndSettle();
    }
  }
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await reveal(t, f);
  await t.enterText(f, text);
  await t.pump();
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('first run → rates → manual entry → result → history', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);

    final state = AppState(MemoryStore());
    await t.pumpWidget(JewelleryCostApp(state: state));
    expect(find.text('Today\'s gold rates'), findsOneWidget);

    // Validation: empty + negative
    await tapKey(t, 'saveRates');
    expect(find.text('Required'), findsOneWidget);
    // Only the 24K rate is entered.
    expect(find.byKey(const Key('rate_k22')), findsNothing);

    // Rates are entered per 10 g by default and stored per gram.
    await enter(t, 'rate_k24', '0');
    await tapKey(t, 'saveRates');
    expect(find.text('Must be greater than 0'), findsOneWidget);
    await enter(t, 'rate_k24', '92105.26');
    // Derived rates are previewed before saving (18K = 76%).
    expect(find.text('₹70,000.00'), findsOneWidget);
    await tapKey(t, 'saveRates');

    expect(find.text('Scan Jewellery Tag'), findsOneWidget);
    expect(find.text('₹70,000.00'), findsOneWidget); // 18K per 10 g
    expect(state.rates!.rateFor(Purity.k18), closeTo(7000, 0.001));
    expect(state.rates!.rateFor(Purity.k22), closeTo(8473.68, 0.01));
    expect(state.rates!.rateFor(Purity.k20), closeTo(7736.84, 0.01));
    expect(state.rates!.rateFor(Purity.k14), closeTo(5526.32, 0.01));
    expect(state.rates!.rateFor(Purity.k9), closeTo(3684.21, 0.01));

    expect(find.byKey(const Key('historyButton')), findsOneWidget);
    await tapKey(t, 'manualEntry');
    // New entries get the next automatic tag number.
    expect(
      (t.widget(find.byKey(const Key('tagNumber'))) as TextField)
          .controller!
          .text,
      'DJ-0001',
    );
    await enter(t, 'tagNumber', 'DR-18-0425');
    await tapKey(t, 'calculate');
    // Gold weight / purity / making / GST missing
    expect(find.text('Gold weight is required'), findsOneWidget);

    // 18K is preselected for a new item.
    expect(find.textContaining('₹7,000.00 per gram'), findsOneWidget);
    await enter(t, 'goldWeight', '10');
    // No diamond/stone lines until Add is tapped.
    expect(find.byKey(const Key('stone.0.weight')), findsNothing);
    expect(find.text('Exclude diamond value'), findsNothing);
    await reveal(t, find.byKey(const Key('add_diamond')));
    await tapKey(t, 'add_diamond');
    await reveal(t, find.byKey(const Key('add_stone')));
    await tapKey(t, 'add_stone');
    TextField field(String k) => t.widget(find.byKey(Key(k))) as TextField;
    expect(field('stone.0.rate').controller!.text, '70000');
    expect(field('stone.1.rate').controller!.text, '');
    await enter(t, 'stone.0.weight', '0.5');
    await enter(t, 'stone.0.rate', '30000');
    await enter(t, 'stone.1.weight', '0.2');
    await enter(t, 'stone.1.rate', '5000');
    final pct = find.descendant(
      of: find.byKey(const Key('makingMethod')),
      matching: find.text('% of gold'),
    );
    await reveal(t, pct);
    await t.tap(pct);
    await t.pumpAndSettle();
    await enter(t, 'makingValue', '10');
    // GST defaults to 3%; wastage is no longer part of the app.
    expect(find.byKey(const Key('wastageMethod')), findsNothing);
    await tapKey(t, 'calculate');

    expect(find.text('Damiyaas Jewelers'), findsOneWidget);
    expect(find.textContaining('Jewellery Cost Estimate'), findsOneWidget);
    expect(find.byKey(const Key('total')), findsOneWidget);
    expect(
      (t.widget(find.byKey(const Key('total'))) as Text).data,
      // gold 70,000 + diamond 15,000 + stone 1,000 + making 7,000
      // = 93,000; GST 3% = 2,790.
      '₹95,790.00',
    );
    await reveal(t, find.byKey(const Key('sendWhatsApp')));
    expect(find.byKey(const Key('sendWhatsApp')), findsOneWidget);

    // Saved to history automatically, without tapping Save.
    expect(state.history.all(), hasLength(1));
    await reveal(t, find.text('Saved to History'));
    expect(find.text('Saved to History'), findsOneWidget);
    expect(state.history.all().single.result.totalPaise, 9579000);

    // Purity can be switched on the summary; the saved record follows.
    await t.drag(find.byKey(const Key('resultList')), const Offset(0, 3000));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('resultPurity')));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('22K ·').last);
    await t.pumpAndSettle();
    // 22K = 92% of 24K = ₹8,473.68/g: gold 84,736.84; diamond 15,000;
    // stone 1,000; making 10% 8,473.68 → 1,09,210.52 + GST 3,276.32.
    expect(
      (t.widget(find.byKey(const Key('total'))) as Text).data,
      '₹1,12,486.84',
    );
    expect(state.history.all(), hasLength(1));
    expect(state.history.all().single.input.purity, Purity.k22);
    expect(state.history.all().single.result.totalPaise, 11248684);
  });

  testWidgets('uncertain scanned fields must be confirmed', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);

    final state = AppState(MemoryStore());
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: DetailsFormScreen(
            parsed: const TagParser().parse(
              'Tag No: CH-0091\nPurity: 22K\nGW 1O.5O g',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Confirm 1 highlighted field'), findsOneWidget);
    await tapKey(t, 'calculate');
    expect(find.text('Please confirm scanned values'), findsOneWidget);
    await t.tap(find.text('Review'));
    await t.pumpAndSettle();
    await reveal(t, find.text('Confirm'));
    await t.tap(find.text('Confirm').first);
    await t.pumpAndSettle();
    expect(find.text('Calculate Cost'), findsOneWidget);
  });

  testWidgets('scanned real tag: FANCY CUT stays a diamond in the estimate', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 7000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);

    final state = AppState(MemoryStore());
    await state.saveRates(
      GoldRates(
        perGram: const {
          Purity.k14: 4100,
          Purity.k18: 5300,
          Purity.k22: 6450,
          Purity.k24: 7000,
        },
        updatedAt: DateTime(2026, 10, 1),
        quotedPerGrams: 10,
      ),
    );
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: DetailsFormScreen(
            parsed: const TagParser().parse(
              '4 G.Wt :6.410 14K :\n© N.Wt:5.886 :\n\'  DIA\\0.38\\700 |\n'
              '| DIA\\0.11\\750\n~#NEANCY CUT) 2.13\\850 |\n',
            ),
          ),
        ),
      ),
    );
    await enter(t, 'makingValue', '1200');
    await tapKey(t, 'calculate');
    expect(find.text('Diamond value'), findsOneWidget);
    expect(find.text('Stone value'), findsNothing);
    expect(find.text('₹2,15,900.00'), findsOneWidget); // 26,600+8,250+1,81,050
  });

  testWidgets('labour default: 10% without diamonds, ₹1,500/g with diamonds', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 7000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(MemoryStore());
    Future<void> open(String tagText) async {
      await t.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            key: UniqueKey(),
            theme: buildTheme(),
            home: DetailsFormScreen(parsed: const TagParser().parse(tagText)),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    String making() =>
        (t.widget(find.byKey(const Key('makingValue'))) as TextField)
            .controller!
            .text;

    // Plain gold tag: 10% of gold value.
    await open('N.Wt :5.000 22K');
    expect(making(), '10');
    expect(find.textContaining('10% of gold value'), findsOneWidget);

    // Tag with diamonds: ₹1,500 per gram.
    await open('N.Wt :5.886 14K\nDIA\\0.38\\700');
    expect(making(), '1500');
    expect(find.textContaining('₹1,500 per gram'), findsOneWidget);

    // Removing the diamond weight switches back to 10% while still automatic.
    await enter(t, 'stone.0.weight', '0');
    expect(making(), '10');

    // Typing your own value stops the automatic default.
    await enter(t, 'makingValue', '1200');
    await enter(t, 'stone.0.weight', '0.38');
    expect(making(), '1200');
  });
  testWidgets('tag without purity or stones: 18K, no stone lines', (t) async {
    t.view.physicalSize = const Size(1080, 7000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(MemoryStore());
    await state.saveRates(
      GoldRates.fromBase24(perGram24: 10000, updatedAt: DateTime(2026, 10, 1)),
    );
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: DetailsFormScreen(
            parsed: const TagParser().parse('N.Wt :2.000'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('purityDefaultHint')), findsOneWidget);
    expect(find.textContaining('(18K): ₹7,600.00 per gram'), findsOneWidget);
    expect(find.byKey(const Key('stone.0.weight')), findsNothing);
    expect(find.text('Exclude diamond value'), findsNothing);
    expect(find.text('Exclude stone value'), findsNothing);

    await tapKey(t, 'add_polki');
    expect(
      (t.widget(find.byKey(const Key('stone.0.rate'))) as TextField)
          .controller!
          .text,
      '70000',
    );
    await tapKey(t, 'removeStone_0');
    await tapKey(t, 'calculate');
    // 2 g × 7,600 = 15,200 + making 10% 1,520 = 16,720 + GST 501.60.
    expect(
      (t.widget(find.byKey(const Key('total'))) as Text).data,
      '₹17,221.60',
    );
  });
}
