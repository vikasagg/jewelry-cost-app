import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/billing/bill.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/pricing/pricing_engine.dart';
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

  testWidgets('Generate Bill: customer details, payment mode, bill screen', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(MemoryStore(), clock: () => DateTime(2026, 10, 18));
    await state.saveRates(rates);
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: ResultScreen(input: input, ratesSnapshot: rates),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Generate Bill'), findsOneWidget);

    await t.tap(find.byKey(const Key('generateBill')));
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
    expect(find.text('Asha Verma'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);
    expect(
      (t.widget(find.byKey(const Key('billPayment'))) as Text).data,
      'Payment mode: UPI',
    );
    expect(find.byKey(const Key('billPrint')), findsOneWidget);
    expect(find.byKey(const Key('billWhatsApp_919717593594')), findsOneWidget);
    expect(find.byKey(const Key('billWhatsApp_919667725005')), findsOneWidget);

    final id = state.history.all().single.id;
    final bill = state.billFor(id)!;
    expect(bill.billNo, 'DJB-0001');
    expect(bill.payment, PaymentMode.upi);

    // Back on the summary the button now opens the saved bill.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('View Bill DJB-0001'), findsOneWidget);
  });

  test(
    'bill text and PDF carry customer, break-up, total and payment',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final r = const PricingEngine().calculate(input, rates.perGram).result!;
      final bill = Bill(
        billNo: 'DJB-0007',
        customerName: 'Asha Verma',
        phone: '9876543210',
        address: 'Sector 14',
        createdAt: DateTime(2026, 10, 18, 15, 5),
      );
      final text = buildBillText(bill, input, r);
      for (final part in [
        'Damiyaas Jewelers',
        'Bill DJB-0007',
        'Customer: Asha Verma',
        'Phone: 9876543210',
        'Gold value (10.000 g × ₹9,200.00/g): ₹92,000.00',
        'Diamond — DIA (0.50 ct × ₹70,000.00/ct): ₹35,000.00',
        'Making / labour (16% of gold value): ₹14,720.00',
        'GST @ 3%',
        'Payment: Cash',
      ]) {
        expect(text, contains(part));
      }
      expect(text, contains('*TOTAL: ${'₹'}'));
      final pdf = await buildBillPdf(bill, input, r);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    },
  );
}
