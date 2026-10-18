import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/ocr/tag_parser.dart';
import 'package:jewellery_cost/ui/screens/scan_screen.dart';
import 'package:jewellery_cost/ui/theme.dart';

/// Unclear values are confirmed or corrected on the scan page itself.
void main() {
  final pixel = img.encodePng(img.Image(width: 1, height: 1));

  Future<AppState> open(WidgetTester t, String tagText) async {
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
          home: ScanScreen(
            initialImage: pixel,
            initialResult: const TagParser().parse(tagText),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return state;
  }

  ButtonStyleButton continueButton(WidgetTester t) =>
      t.widget<ButtonStyleButton>(find.byKey(const Key('continueScan')));

  /// Continue makes the photo thumbnail in a background isolate first.
  Future<void> continueToForm(WidgetTester t) async {
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('continueScan')));
      for (
        var i = 0;
        i < 50 && find.byKey(const Key('goldWeight')).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    await t.pumpAndSettle();
  }

  String fieldText(WidgetTester t, String key) =>
      (t.widget(find.byKey(Key(key))) as TextField).controller!.text;

  testWidgets('confirm an unclear value, then the form needs nothing', (
    t,
  ) async {
    await open(t, 'Tag No: CH-0091\nPurity: 22K\nGW 1O.5O g');
    expect(find.byKey(const Key('confirmHint')), findsOneWidget);
    expect(find.text('Confirm 1 value to continue'), findsOneWidget);
    expect(continueButton(t).onPressed, isNull);

    await t.tap(find.byKey(const Key('confirm_goldWeight')));
    await t.pumpAndSettle();
    expect(find.text('Continue to Calculate'), findsOneWidget);
    expect(find.byKey(const Key('confirmHint')), findsNothing);

    await continueToForm(t);
    expect(fieldText(t, 'goldWeight'), '10.5');
    expect(find.textContaining('highlighted'), findsNothing);
  });

  testWidgets('"Confirm all" clears every unclear value at once', (t) async {
    await open(t, 'N.Wt :5.886 14K\nDIA\\0.38\\700\nDIA\\0.11\\750\nGW 6.410');
    expect(find.text('Confirm 4 values to continue'), findsOneWidget);
    await t.tap(find.byKey(const Key('confirmAll')));
    await t.pumpAndSettle();
    expect(find.text('Continue to Calculate'), findsOneWidget);
    await continueToForm(t);
    expect(fieldText(t, 'goldWeight'), '5.886');
    expect(fieldText(t, 'grossWeight'), '6.41');
    expect(find.textContaining('highlighted'), findsNothing);
  });

  testWidgets('a missing gold weight is entered on the scan page', (t) async {
    await open(t, 'Purity: 18K\nTag No: R-1');
    expect(find.text('Not found on the tag — enter it'), findsOneWidget);
    expect(continueButton(t).onPressed, isNull);

    // Typed straight into the field on the scan page.
    await t.enterText(find.byKey(const Key('field_goldWeight')), '4.25');
    await t.pump();
    expect(continueButton(t).onPressed, isNotNull);

    await continueToForm(t);
    expect(fieldText(t, 'goldWeight'), '4.25');
  });

  testWidgets('stone lines: edit one, confirm the rest together', (t) async {
    // No gross weight, so the merged weights/codes cannot be verified.
    await open(t, 'N.Wt:5.886 14K\nDIA0.38700\nDIA0.11750');
    expect(find.text('Confirm 2 values to continue'), findsOneWidget);

    await t.tap(find.byKey(const Key('edit_stone.0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Polki').last);
    await t.enterText(find.byKey(const Key('editValue')), '0.4');
    await t.tap(find.byKey(const Key('editSave')));
    await t.pumpAndSettle();
    expect(find.text('Confirm 1 value to continue'), findsOneWidget);
    expect(find.textContaining('Polki'), findsWidgets);

    await t.tap(find.byKey(const Key('confirm_stone.1')));
    await t.pumpAndSettle();
    await continueToForm(t);
    expect(fieldText(t, 'stone.0.weight'), '0.4');
    expect(fieldText(t, 'stone.1.weight'), '0.11');
    expect(find.textContaining('highlighted'), findsNothing);
  });

  testWidgets('the tag photo is shown on the summary and kept in history', (
    t,
  ) async {
    final state = await open(t, 'Tag No: R-7\nPurity: 22K\nN.Wt 4.000 g');
    await continueToForm(t);
    await t.tap(find.byKey(const Key('calculate')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('resultPhoto')), findsOneWidget);
    final saved = state.history.all().single;
    expect(state.imageFor(saved.id), isNotNull);

    await state.deleteCalculation(saved.id);
    expect(state.imageFor(saved.id), isNull);
  });

  test('confirm() re-checks the weight balance with corrected values', () {
    final p = const TagParser().parse(
      'G.Wt:6.410 14K\nN.Wt:5.886\nDIA\\0.38\\700\nDIA\\0.11\\750',
    );
    expect(p.weightBalance!.balances, isFalse); // FANCY CUT line not read
    final fixed = p.confirm('stone.1', (0.11 + 2.13, StoneKind.diamond));
    expect(fixed.weightBalance!.balances, isTrue);
    expect(fixed.stones[1].weight.confidence, FieldConfidence.high);
  });
}
