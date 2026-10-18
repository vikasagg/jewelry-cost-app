import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/billing/bill.dart';
import 'package:jewellery_cost/core/money.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/pricing/pricing_engine.dart';
import 'package:jewellery_cost/ui/screens/bill_screen.dart';
import 'package:jewellery_cost/ui/screens/result_screen.dart';
import 'package:jewellery_cost/ui/theme.dart';

void main() {
  final rates = GoldRates.fromBase24(
    perGram24: 10000,
    updatedAt: DateTime(2026, 10, 18),
  );
  const input = JewelleryInput(
    tagNumber: 'CH1619',
    purity: Purity.k22,
    goldWeight: 10,
    makingMethod: MakingMethod.percentOfGold,
    makingValue: 16,
    gst: GstConfig(ratePercent: 3),
    stones: [
      StoneLine(
        kind: StoneKind.diamond,
        label: 'DIA',
        weightCt: 0.5,
        ratePerCt: 70000,
      ),
    ],
  );

  const ring = JewelleryInput(
    tagNumber: 'LGR220',
    itemName: 'Ladies ring',
    purity: Purity.k18,
    goldWeight: 4,
    makingMethod: MakingMethod.perGram,
    makingValue: 1200,
    gst: GstConfig(ratePercent: 3),
  );
  PricingResult price(JewelleryInput i) =>
      const PricingEngine().calculate(i, rates.perGram).result!;

  testWidgets('Generate Bill: pick two products, customer, product table', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    var minute = 0;
    final state = AppState(
      MemoryStore(),
      clock: () => DateTime(2026, 10, 18, 12, minute++),
    );
    await state.saveRates(rates);
    final first = await state.saveCalculation(
      input: input,
      ratesSnapshot: rates,
      result: price(input),
    );
    final second = await state.saveCalculation(
      input: ring,
      ratesSnapshot: rates,
      result: price(ring),
    );
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: ResultScreen(
            input: input,
            ratesSnapshot: rates,
            recordId: first.id,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('generateBill')));
    await t.pumpAndSettle();

    // The current estimate is ticked; add the ring.
    expect(find.text('Select products'), findsOneWidget);
    expect(find.textContaining('Next · 1 product · '), findsOneWidget);
    await t.tap(find.byKey(Key('billItem_${second.id}')));
    await t.pumpAndSettle();
    final sum = first.result.totalPaise + second.result.totalPaise;
    expect(
      find.text('Next · 2 products · ${formatPaise(sum)}'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('billItemsNext')));
    await t.pumpAndSettle();

    // Name is required; phone must be 10 digits.
    await t.enterText(find.byKey(const Key('billPhone')), '98765');
    await t.tap(find.byKey(const Key('billOk')));
    await t.pumpAndSettle();
    expect(find.text('Enter the customer name'), findsOneWidget);
    expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
    await t.enterText(find.byKey(const Key('billName')), 'Asha Verma');
    await t.enterText(find.byKey(const Key('billPhone')), '98765 43210');
    await t.enterText(
      find.byKey(const Key('billAddress')),
      'Sector 14, Gurugram',
    );
    await t.tap(find.byKey(const Key('pay_upi')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('billOk')));
    await t.pumpAndSettle();

    expect(find.text('Bill DJB-0001'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);
    expect(find.text('Products (2)'), findsOneWidget);
    expect(find.text('CH1619'), findsOneWidget);
    expect(find.text('LGR220 · Ladies ring'), findsOneWidget);
    expect(
      (t.widget(find.byKey(const Key('billTotal'))) as Text).data,
      formatPaise(sum),
    );
    expect(
      (t.widget(find.byKey(const Key('billPayment'))) as Text).data,
      'Payment mode: UPI',
    );
    expect(find.byKey(const Key('billPrint')), findsOneWidget);
    expect(find.byKey(const Key('billPrintPaper')), findsOneWidget);

    final bill = state.billFor(second.id)!;
    expect(bill.billNo, 'DJB-0001');
    expect(bill.payment, PaymentMode.upi);
    expect(bill.items.map((i) => i.recordId), [first.id, second.id]);

    // Back on the summary the button now opens the saved bill.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('View Bill DJB-0001'), findsOneWidget);
  });

  Bill twoItemBill() => Bill(
    billNo: 'DJB-0007',
    customerName: 'Asha Verma',
    phone: '9876543210',
    address: 'Sector 14',
    createdAt: DateTime(2026, 10, 18, 15, 5),
    items: [
      BillItem(recordId: 'a', input: input, result: price(input)),
      BillItem(recordId: 'b', input: ring, result: price(ring)),
    ],
  );

  test('bill rows, totals and PDF for two products', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final b = twoItemBill();
    final rows = billRows(b);
    expect(rows.length, 2);
    expect(rows[0].cells, [
      '1',
      'CH1619',
      '22K',
      '10.000',
      '₹9,200.00',
      '₹92,000.00',
      '₹35,000.00',
      '₹14,720.00',
      formatPaise(price(input).gstPaise),
      formatPaise(price(input).totalPaise),
    ]);
    expect(
      rows[0].details,
      contains('DIA 0.50 ct × ₹70,000.00/ct = ₹35,000.00'),
    );
    expect(rows[1].cells[6], '—');
    expect(rows[1].cells[7], '₹4,800.00'); // ₹1,200/g × 4 g
    expect(b.totalPaise, price(input).totalPaise + price(ring).totalPaise);
    expect(b.gstSummary.single.$1, 'GST @ 3%');
    expect(b.gstSummary.single.$2, b.gstPaise);
    expect(billCaption(b), contains('2 items'));
    final back = Bill.fromJson(b.toJson());
    expect(back.items.length, 2);
    expect(back.totalPaise, b.totalPaise);
    final pdf = await buildBillPdf(b);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  testWidgets('Android Print sends the PDF to both WhatsApp numbers', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final calls = <Map<Object?, Object?>>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('damiyaas/whatsapp'),
      (c) async {
        calls.add(c.arguments as Map<Object?, Object?>);
        return 'done';
      },
    );
    final bill = twoItemBill();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: BillScreen(bill: bill),
      ),
    );
    // Let the PDF build (font loading runs outside fake async).
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await t.pump();
    expect(find.text('Print — send PDF'), findsOneWidget);
    await t.tap(find.byKey(const Key('billPrint')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump();
    expect(calls.map((c) => c['phone']), billWhatsAppNumbers);
    expect(calls.first['name'], 'bill-DJB-0007.pdf');
    expect(
      String.fromCharCodes((calls.first['bytes'] as Uint8List).take(4)),
      '%PDF',
    );
    expect(find.textContaining('Bill sent to'), findsOneWidget);
  });
}
