import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/main.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/stock/stock_book.dart';
import 'package:jewellery_cost/stock/stock_models.dart';
import 'package:jewellery_cost/stock/stock_report.dart';

void main() {
  var now = DateTime(2026, 10, 17, 10);
  DateTime clock() => now;

  /// Counts every category: 10 each, with [overrides].
  Future<DailyStock> countAll(
    StockBook book,
    DailyStock d, [
    Map<String, int> overrides = const {},
  ]) async {
    for (final i in stockItems) {
      d = await book.setCount(d, i.code, overrides[i.code] ?? 10);
    }
    return d;
  }

  group('StockBook', () {
    late MemoryStore store;
    late StockBook book;
    setUp(() async {
      now = DateTime(2026, 10, 17, 10);
      store = MemoryStore();
      book = StockBook(store, clock: clock);
      await book.pins.setPin('Asha', '4321');
    });

    test(
      'first count sets the baseline; verified closing carries forward',
      () async {
        var d = await book.open(book.today);
        expect(d.hasOpening, isFalse);
        expect(d.totalExpected, 0);

        d = await countAll(book, d);
        expect(d.difference('LGR'), isNull); // nothing to compare yet
        expect(d.totalDifference, 0);
        await expectLater(book.submit(d), throwsA(isA<StockException>()));
        d = await book.setEmployee(d, 'Ravi');
        d = await book.submit(d);
        expect(d.status, StockStatus.submitted);

        await expectLater(
          book.verify(d, manager: 'Asha', pin: '0000'),
          throwsA(isA<StockException>()),
        );
        d = await book.verify(d, manager: 'Asha', pin: '4321');
        expect(d.status, StockStatus.verified);
        expect(d.approvedBy, 'Asha');

        // Next day: yesterday's verified count is today's expected opening.
        now = DateTime(2026, 10, 18, 10);
        var t = await book.open(book.today);
        expect(t.openingFrom, '2026-10-17');
        expect(t.expected('LGR'), 10);
        expect(t.employee, 'Ravi'); // remembered
        t = await countAll(book, t, {'LGR': 9, 'GGR': 11, 'CHAIN': 7});
        expect(t.difference('LGR'), -1);
        expect(t.difference('GGR'), 1);
        expect(t.groupExpected('Ring'), 20);
        expect(t.groupCount('Ring'), 20);
        expect(t.totalExpected, 140);
        expect(t.totalCount, 137);
        expect(t.totalDifference, -3);
        expect(t.unexplained.map((i) => i.code), ['LGR', 'GGR', 'CHAIN']);
        t = await book.setRemark(t, 'CHAIN', '3 sent for polishing');
        expect(t.unexplained.map((i) => i.code), ['LGR', 'GGR']);

        // Yesterday's closing is never changed to hide today's difference.
        expect(book.byDate('2026-10-17')!.counts['CHAIN'], 10);
      },
    );

    test('adjustments need the manager PIN and only change today', () async {
      var d = await countAll(book, await book.open(book.today));
      d = await book.setEmployee(d, 'Ravi');
      d = await book.verify(await book.submit(d), manager: 'Asha', pin: '4321');

      now = DateTime(2026, 10, 18, 10);
      var t = await book.open(book.today);
      await expectLater(
        book.addAdjustment(
          t,
          code: 'BANGLE',
          qty: 2,
          reason: 'Received',
          manager: 'Asha',
          pin: '1111',
        ),
        throwsA(isA<StockException>()),
      );
      t = await book.addAdjustment(
        t,
        code: 'BANGLE',
        qty: 2,
        reason: 'Received from workshop',
        manager: 'Asha',
        pin: '4321',
      );
      expect(t.previousClosing('BANGLE'), 10);
      expect(t.expected('BANGLE'), 12);
      expect(t.audit.last.action, 'Adjustment approved');
      expect(book.byDate('2026-10-17')!.counts['BANGLE'], 10);
    });

    test(
      'verified days are locked; reopening needs PIN, reason and order',
      () async {
        var d = await countAll(book, await book.open(book.today));
        d = await book.setEmployee(d, 'Ravi');
        d = await book.verify(
          await book.submit(d),
          manager: 'Asha',
          pin: '4321',
        );
        await expectLater(
          book.setCount(d, 'LGR', 1),
          throwsA(isA<StockException>()),
        );

        // Today's draft picks up the opening once yesterday is verified.
        now = DateTime(2026, 10, 18, 10);
        var t = await countAll(book, await book.open(book.today));
        t = await book.verify(
          await book.submit(t),
          manager: 'Asha',
          pin: '4321',
        );

        await expectLater(
          book.reopen(d, manager: 'Asha', pin: '4321', reason: 'Recount'),
          throwsA(isA<StockException>()), // a later day depends on it
        );
        t = await book.reopen(
          t,
          manager: 'Asha',
          pin: '4321',
          reason: 'Recount',
        );
        expect(t.status, StockStatus.draft);
        expect(t.approvedBy, isNull);
        expect(t.audit.last.detail, 'Recount');
      },
    );

    test(
      'a draft follows a previous day verified after it was started',
      () async {
        var d = await countAll(book, await book.open('2026-10-17'));
        now = DateTime(2026, 10, 18, 10);
        var t = await book.open(book.today);
        expect(t.hasOpening, isFalse);

        d = await book.setEmployee(d, 'Ravi');
        await book.verify(await book.submit(d), manager: 'Asha', pin: '4321');
        t = await book.open(book.today);
        expect(t.openingFrom, '2026-10-17');
        expect(t.audit.last.action, 'Opening updated');
      },
    );

    test(
      'personal PINs are stored hashed; changing needs the old one',
      () async {
        expect(store.keys.map(store.get), isNot(contains('4321')));
        await expectLater(
          book.pins.setPin('Asha', '9999', currentPin: '0000'),
          throwsA(isA<StockException>()),
        );
        await book.pins.setPin('Asha', '9999', currentPin: '4321');
        await book.pins.verify('asha', '9999'); // name case ignored
        await expectLater(
          book.pins.verify('Asha', '4321'),
          throwsA(isA<StockException>()),
        );
        expect(book.pins.hasPin('Ravi'), isFalse);
      },
    );

    test('the counter signs in with a PIN and cannot approve', () async {
      var d = await book.open(book.today);
      await expectLater(
        book.startCount(d, 'Ravi', '1111'),
        throwsA(isA<StockException>()), // no PIN yet
      );
      await book.pins.setPin('Ravi', '2468');
      await expectLater(
        book.startCount(d, 'Ravi', '0000'),
        throwsA(isA<StockException>()),
      );
      d = await book.startCount(d, 'Ravi', '2468');
      expect(d.employee, 'Ravi');
      expect(d.audit.last.action, 'Signed in');
      d = await book.submit(await countAll(book, d));

      // Ravi counted, so Ravi cannot approve — even with his own PIN.
      await expectLater(
        book.verify(d, manager: ' ravi ', pin: '2468'),
        throwsA(
          isA<StockException>().having(
            (e) => e.message,
            'message',
            contains('cannot approve'),
          ),
        ),
      );
      await expectLater(
        book.addAdjustment(
          d.copyWith(status: StockStatus.draft),
          code: 'LGR',
          qty: 1,
          reason: 'x',
          manager: 'Ravi',
          pin: '2468',
        ),
        throwsA(isA<StockException>()),
      );
      // Someone without a PIN cannot approve either.
      await expectLater(
        book.verify(d, manager: 'Meena', pin: '1234'),
        throwsA(
          isA<StockException>().having(
            (e) => e.message,
            'message',
            contains('has not created a PIN'),
          ),
        ),
      );
      d = await book.verify(d, manager: 'Asha', pin: '4321');
      expect(d.approvedBy, 'Asha');
      expect(d.employee, 'Ravi');
    });
  });

  test('stock counts never touch prices, rates or estimates', () async {
    final state = AppState(MemoryStore(), clock: clock);
    final rates = GoldRates.fromBase24(perGram24: 10000, updatedAt: now);
    await state.saveRates(rates);
    await state.stock.pins.setPin('Asha', '4321');
    var d = await countAll(state.stock, await state.stock.open('2026-10-17'));
    d = await state.stock.setEmployee(d, 'Ravi');
    await state.stock.verify(
      await state.stock.submit(d),
      manager: 'Asha',
      pin: '4321',
    );
    expect(state.rates, rates);
    expect(state.history.all(), isEmpty);
  });

  test('WhatsApp summary and PDF include every required part', () async {
    final book = StockBook(MemoryStore(), clock: clock);
    await book.pins.setPin('Asha', '4321');
    var d = await countAll(book, await book.open('2026-10-17'));
    d = await book.setEmployee(d, 'Ravi');
    d = await book.verify(await book.submit(d), manager: 'Asha', pin: '4321');
    now = DateTime(2026, 10, 18, 10);
    var t = await countAll(book, await book.open('2026-10-18'), {'LGR': 9});
    t = await book.setEmployee(t, 'Ravi');
    t = await book.setRemark(t, 'LGR', '1 sent for resizing');
    t = await book.submit(t);

    final text = buildStockSummaryText(t);
    for (final part in [
      'Damiyaas Jewelers',
      '18 Oct 2026',
      'Employee: Ravi',
      '*Ring*: 20 / 19 / -1',
      'LGR (Ladies Gold Ring): 10 / 9 / -1 ⚠',
      '*Watch*: 10 / 10 / 0',
      'Total expected stock: 140',
      'Total physical stock: 139',
      'Overall: *Shortage of 1*',
      'LGR: 1 sent for resizing',
      'Status: Submitted — awaiting manager approval',
    ]) {
      expect(text, contains(part));
    }
    final pdf = await buildStockSummaryPdf(t);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  testWidgets('count on the keypad from the home screen', (t) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(MemoryStore(), clock: clock);
    await t.pumpWidget(JewelleryCostApp(state: state));
    await t.tap(find.byKey(const Key('openStock')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('openTodayStock')));
    await t.pumpAndSettle();
    expect(find.text('Ring'), findsOneWidget);
    expect(find.text('Chashma'), findsOneWidget);
    expect(find.text('Last day'), findsOneWidget);

    // The employee name is mandatory before counting.
    await t.tap(find.byKey(const Key('count_LGR')));
    await t.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.byKey(const Key('keypadDisplay')), findsNothing);
    await t.enterText(find.byKey(const Key('stockEmployee')), 'Ravi');
    await t.pump();

    // First count: Ravi creates his own PIN (entered twice).
    await t.tap(find.byKey(const Key('count_LGR')));
    await t.pumpAndSettle();
    expect(find.text('Create your PIN, Ravi'), findsOneWidget);
    await t.enterText(find.byKey(const Key('userPin')), '2468');
    await t.enterText(find.byKey(const Key('userPinAgain')), '2469');
    await t.tap(find.byKey(const Key('userPinOk')));
    await t.pumpAndSettle();
    expect(find.text('The two PINs do not match'), findsOneWidget);
    await t.enterText(find.byKey(const Key('userPinAgain')), '2468');
    await t.tap(find.byKey(const Key('userPinOk')));
    await t.pumpAndSettle();
    expect(state.stock.pins.hasPin('Ravi'), isTrue);
    expect(
      state.stock.byDate(state.stock.today)!.audit.last.action,
      'Signed in',
    );
    for (final k in ['1', '2']) {
      await t.tap(find.byKey(Key('key_$k')));
      await t.pump();
    }
    await t.tap(find.byKey(const Key('keypadDone')));
    await t.pumpAndSettle();
    expect(state.stock.byDate(state.stock.today)!.counts['LGR'], 12);
    expect(
      (t.widget(find.byKey(const Key('groupTotal_Ring'))) as Text).data,
      'Total 12',
    );
    // First day: no opening yet, so there is no difference to show.
    expect(
      find.descendant(
        of: find.byKey(const Key('totalPhysical')),
        matching: find.text('12'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('diff_LGR')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );

    // A remark on a line.
    await t.tap(find.byKey(const Key('remark_LGR')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('remarkField')), 'Opening stock');
    await t.tap(find.byKey(const Key('remarkSave')));
    await t.pumpAndSettle();
    expect(find.text('“Opening stock”'), findsOneWidget);

    // Submitting needs every category counted.
    await t.enterText(find.byKey(const Key('stockEmployee')), 'Ravi');
    await t.tap(find.byKey(const Key('stockSubmit')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Enter a count for every category'),
      findsOneWidget,
    );
    expect(state.stock.byDate(state.stock.today)!.employee, 'Ravi');
  });

  test('keypad working: + and − add up left to right', () {
    const e = CountExpression('5+3-1');
    expect(e.terms, [5, 3, -1]);
    expect(e.value, 7);
    expect(e.pretty, '5 + 3 − 1');
    expect(e.hasWorking, isTrue);
    expect(const CountExpression('5+').isComplete, isFalse);
    expect(const CountExpression('12').hasWorking, isFalse);
  });

  testWidgets('calculator entry, visible working, 3-second auto-save, date', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    now = DateTime(2026, 10, 18, 10);
    final state = AppState(MemoryStore(), clock: clock);
    await t.pumpWidget(JewelleryCostApp(state: state));
    await t.tap(find.byKey(const Key('openStock')));
    await t.pumpAndSettle();

    // Pick an earlier date on the stock home.
    await t.tap(find.byKey(const Key('stockHomeDate')));
    await t.pumpAndSettle();
    await t.tap(find.text('17'));
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.textContaining('17 Oct 2026'), findsWidgets);
    await t.tap(find.byKey(const Key('openTodayStock')));
    await t.pumpAndSettle();

    // 5 + 3 − 1 on the keypad: every entry and the total are shown.
    await state.stock.pins.setPin('Meena', '1357');
    await t.enterText(find.byKey(const Key('stockEmployee')), 'Meena');
    await t.tap(find.byKey(const Key('count_LGR')));
    await t.pumpAndSettle();
    expect(find.text('PIN for Meena'), findsOneWidget);
    await t.enterText(find.byKey(const Key('userPin')), '0000');
    await t.tap(find.byKey(const Key('userPinOk')));
    await t.pumpAndSettle();
    expect(find.text('Incorrect PIN'), findsOneWidget);
    await t.enterText(find.byKey(const Key('userPin')), '1357');
    await t.tap(find.byKey(const Key('userPinOk')));
    await t.pumpAndSettle();
    for (final k in ['5', '+', '3', '−', '1']) {
      await t.tap(find.byKey(Key('key_$k')));
      await t.pump();
    }
    expect(
      (t.widget(find.byKey(const Key('keypadWorking'))) as Text).data,
      '5 + 3 − 1',
    );
    expect(
      (t.widget(find.byKey(const Key('keypadTotal'))) as Text).data,
      '= 7',
    );
    await t.tap(find.byKey(const Key('keypadDone')));
    await t.pumpAndSettle();
    final day = state.stock.byDate('2026-10-17')!;
    expect(day.counts['LGR'], 7);
    expect(day.entries['LGR'], '5+3-1');
    expect(
      (t.widget(find.byKey(const Key('working_LGR'))) as Text).data,
      '5 + 3 − 1 = 7',
    );

    // Typing is saved within 3 seconds, without leaving the field.
    await t.enterText(find.byKey(const Key('stockEmployee')), 'Meena');
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(state.stock.byDate('2026-10-17')!.employee, 'Meena');
    expect(state.stock.lastSession!.date, '2026-10-17');
    expect(
      (t.widget(find.byKey(const Key('autosaveStatus'))) as Text).data,
      startsWith('Auto-saved 18 Oct 2026'),
    );
  });
}
