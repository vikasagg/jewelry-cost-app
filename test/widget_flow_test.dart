import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/main.dart';
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
    expect(find.text('Save Rates & Continue'), findsOneWidget);

    // Validation: empty + negative
    await tapKey(t, 'saveRates');
    expect(find.text('Required'), findsNWidgets(4));

    await enter(t, 'rate_k14', '4100');
    await enter(t, 'rate_k18', '7000');
    await enter(t, 'rate_k22', '6450');
    await enter(t, 'rate_k24', '0');
    await tapKey(t, 'saveRates');
    expect(find.text('Must be greater than 0'), findsOneWidget);
    await enter(t, 'rate_k24', '7700');
    await tapKey(t, 'saveRates');

    expect(find.text('Scan Jewellery Tag'), findsOneWidget);
    expect(find.text('₹7,000.00'), findsOneWidget);

    await tapKey(t, 'manualEntry');
    await enter(t, 'tagNumber', 'DR-18-0425');
    await tapKey(t, 'calculate');
    // Gold weight / purity / making / GST missing
    expect(find.text('Gold weight is required'), findsOneWidget);

    await t.tap(find.text('18K'));
    await t.pumpAndSettle();
    expect(find.textContaining('₹7,000.00 per gram'), findsOneWidget);
    await enter(t, 'goldWeight', '10');
    await enter(t, 'stone.0.weight', '0.5');
    await enter(t, 'stone.0.rate', '30000');
    await enter(t, 'stone.1.weight', '0.2');
    await enter(t, 'stone.1.rate', '5000');
    final pct = find.descendant(
      of: find.byKey(const Key('makingMethod')),
      matching: find.text('% of gold value'),
    );
    await reveal(t, pct);
    await t.tap(pct);
    await t.pumpAndSettle();
    await enter(t, 'makingValue', '10');
    final wpct = find.descendant(
      of: find.byKey(const Key('wastageMethod')),
      matching: find.text('%'),
    );
    await reveal(t, wpct);
    await t.tap(wpct);
    await t.pumpAndSettle();
    await enter(t, 'wastagePercent', '5');
    await enter(t, 'gstRate', '3');
    await tapKey(t, 'calculate');

    expect(find.text('Jewellery Cost Summary'), findsOneWidget);
    expect(find.byKey(const Key('total')), findsOneWidget);
    expect(
      (t.widget(find.byKey(const Key('total'))) as Text).data,
      '₹99,395.00',
    );

    await tapKey(t, 'saveHistory');
    expect(state.history.all(), hasLength(1));
    expect(state.history.all().single.result.totalPaise, 9939500);
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
}
