import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/main.dart';
import 'package:jewellery_cost/ui/screens/reports/sales_register_screen.dart';
import 'package:jewellery_cost/ocr/ocr_service.dart';
import 'package:jewellery_cost/reports/register_image.dart';
import 'package:jewellery_cost/reports/sales_register.dart';

OcrBox box(String t, double l, double top, double r, double b) =>
    OcrBox(t, left: l, top: top, right: r, bottom: b);

void main() {
  testWidgets('Reports → Today\'s Sales: photo, check, image', (t) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(
      MemoryStore(),
      clock: () => DateTime(2026, 11, 1, 18),
    );
    await t.pumpWidget(JewelleryCostApp(state: state));
    await t.tap(find.byKey(const Key('openReports')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('todaysSales')));
    await t.pumpAndSettle();
    expect(find.text('Today · 1 Nov 2026'), findsOneWidget);

    // Swap in a fake reader and photo for this screen.
    final page = OcrPage.fromJson(
      jsonDecode(
            File('test/fixtures/register_page_ocr.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    Navigator.of(t.element(find.byType(Scaffold).last)).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SalesRegisterScreen(
          ocr: FakeOcr(page),
          pickImage: (_) async => Uint8List.fromList([1, 2, 3]),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('registerGallery')));
    await t.pumpAndSettle();
    expect(find.text('Register lines (10)'), findsOneWidget);
    expect(find.text('Part 1 · 10 lines'), findsOneWidget);
    expect(find.byKey(const Key('registerUnchecked')), findsOneWidget);
    // The same photo again: nothing new.
    await t.tap(find.byKey(const Key('registerGallery')));
    await t.pumpAndSettle();
    expect(find.text('Register lines (10)'), findsOneWidget);
    expect(find.textContaining('10 already listed skipped'), findsOneWidget);
    expect(find.text('Pintu Ji'), findsOneWidget);

    // Check line 1, and fix line 3 (Amar G, G-Chain sale).
    await t.tap(find.byKey(const Key('registerRow_0')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('entryType_R')));
    await t.tap(find.byKey(const Key('entryOk')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('registerRow_2')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('entryName')), 'Amar G');
    await t.enterText(find.byKey(const Key('entryItem')), 'G-Chain sale');
    await t.tap(find.byKey(const Key('entryOk')));
    await t.pumpAndSettle();
    // Delete the crossed-out line (6th) with its row's delete button;
    // Undo brings it back, then delete it for good.
    await t.tap(find.byKey(const Key('registerDelete_5')));
    await t.pumpAndSettle();
    expect(state.sales.byDate('2026-11-01').entries.length, 9);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(state.sales.byDate('2026-11-01').entries.length, 10);
    await t.tap(find.byKey(const Key('registerDelete_5')));
    await t.pumpAndSettle();
    expect(
      state.sales.byDate('2026-11-01').entries.map((e) => e.no),
      List.generate(9, (i) => i + 1), // renumbered
    );

    final saved = state.sales.byDate('2026-11-01');
    expect(saved.entries.length, 9);
    expect(saved.entries[0].numberLabel, '1 / R');
    expect(saved.entries[0].checked, isTrue);
    expect(saved.entries[2].name, 'Amar G');
    expect(saved.unchecked, 7);

    await t.tap(find.byKey(const Key('createRegisterImage')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('createAnyway')));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('registerImage')), findsOneWidget);
    expect(find.byKey(const Key('shareRegisterImage')), findsOneWidget);

    // WhatsApp (Android app): the PNG goes straight to WhatsApp.
    final sent = <Map<Object?, Object?>>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('damiyaas/whatsapp'),
      (c) async {
        sent.add(c.arguments as Map<Object?, Object?>);
        return 'done';
      },
    );
    await t.tap(find.byKey(const Key('whatsappRegisterImage')));
    await t.pump();
    expect(sent.single['mime'], 'image/png');
    expect(sent.single['phone'], '');
    expect(sent.single['name'], 'customer-register-2026-11-01.png');

    // Back on the list: clear all lines.
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('registerClearAll')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('clearAllOk')));
    await t.pumpAndSettle();
    expect(state.sales.byDate('2026-11-01').entries, isEmpty);
    expect(find.text('Register lines (0)'), findsOneWidget);
  });

  testWidgets('register image is a PNG table', (t) async {
    await t.runAsync(() async {
      await loadAppFonts();
      final png = await renderRegisterPng(
        const SalesRegister(
          date: '2026-11-01',
          entries: [
            SalesEntry(
              no: 1,
              type: 'N',
              name: 'Shubhir Ji',
              mobile: '9810106869',
              item: 'Silver coin sale',
            ),
            SalesEntry(
              no: 2,
              type: 'N',
              name: 'Isha Ji',
              item: 'Silver coin sale',
            ),
            SalesEntry(
              no: 3,
              type: 'R',
              name: 'Pintu Ji',
              item: 'Bali exchange',
            ),
            SalesEntry(no: 4, type: 'R', name: 'Priya G', item: 'G-Ring sale'),
            SalesEntry(
              no: 5,
              type: 'N',
              name: 'Mosa Ji',
              item: 'Silver coin sale',
            ),
          ],
        ),
      );
      expect(png.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
      const out = String.fromEnvironment('REGISTER_PNG_OUT');
      if (out.isNotEmpty) File(out).writeAsBytesSync(png);
    });
  });

  test('sample register photo: rows line up and items are cleaned', () {
    // PaddleOCR output for the shop's register photo (rows 4–12).
    final page = OcrPage.fromJson(
      jsonDecode(
            File('test/fixtures/register_page_ocr.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    final rows = parseRegisterPage(page, startNo: 4);
    expect(rows.length, 10); // includes the crossed-out line
    expect(rows.map((r) => r.no), [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
    expect(rows.every((r) => !r.checked), isTrue);
    expect(rows[0].name, 'Pintu Ji');
    expect(rows[0].item, 'Bali exchange');
    expect(rows[3].name, 'Shivam');
    expect(rows[3].item, 'Silver payal sale');
    expect(rows[4].name, 'Mukesh Ji');
    expect(rows[6].item, 'G-Chain sale');
    expect(rows[7].item, 'Mala sale');
    expect(rows[8].item, 'G-Coin sale');
    expect(rows[9].type, 'N');
    expect(rows[9].item, 'Silver coin sale');
  });

  test('a page in two overlapping photos merges without repeats', () {
    final page = OcrPage.fromJson(
      jsonDecode(
            File('test/fixtures/register_page_ocr.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    // Top photo: lines down to Deepanshu; bottom photo: from the struck
    // line down (three lines overlap).
    OcrPage part(bool Function(OcrBox) keep) => OcrPage(
      width: page.width,
      height: page.height,
      boxes: page.boxes.where(keep).toList(),
    );
    final top = parseRegisterPage(part((b) => b.centerY < 720));
    final bottom = parseRegisterPage(part((b) => b.centerY > 590));
    expect(top.length + bottom.length, greaterThan(10));

    var r = const SalesRegister(date: '2026-11-01');
    final m1 = r.mergePart(top);
    r = m1.register;
    final m2 = r.mergePart(bottom);
    r = m2.register;
    expect(m2.skipped, greaterThan(0));
    expect(r.entries.length, 10);
    expect(r.entries.map((e) => e.no), List.generate(10, (i) => i + 1));
    expect(r.parts, {1: m1.added, 2: m2.added});
    expect(r.entries.last.item, 'Silver coin sale');

    // Bottom photo taken first: move part 2 up, numbers follow.
    var x = const SalesRegister(date: '2026-11-01');
    x = x.mergePart(bottom).register;
    x = x.mergePart(top).register;
    expect(x.entries.length, 10);
    x = x.movePartFirst(2);
    expect(x.entries.first.name, 'Pintu Ji');
    expect(x.entries.map((e) => e.no), List.generate(10, (i) => i + 1));
    x = x.removePart(1);
    expect(x.parts.keys, [2]);
    expect(x.entries.first.no, 1);

    // The same photo twice adds nothing.
    final again = r.mergePart(parseRegisterPage(page));
    expect(again.added, 0);
    expect(again.skipped, 10);
  });

  test('markers, mobile numbers and one-sided rows', () {
    final page = OcrPage(
      width: 1000,
      height: 600,
      boxes: [
        box('Date', 700, 10, 760, 30),
        box('1', 20, 100, 40, 130),
        box('N', 60, 100, 80, 130),
        box('Shubhir ji', 120, 98, 300, 132),
        box('98101 06869', 400, 100, 560, 130),
        box('Silver coin', 700, 110, 880, 140),
        box('R', 60, 160, 80, 190),
        box('Pintu Ji', 120, 158, 280, 192),
        box('G-Chain Sale', 700, 170, 900, 200),
        box('Mala sale', 700, 230, 880, 260), // name not read
      ],
    );
    final rows = parseRegisterPage(page);
    expect(rows.length, 3);
    expect(rows[0].numberLabel, '1 / N');
    expect(rows[0].name, 'Shubhir Ji');
    expect(rows[0].mobile, '9810106869');
    expect(rows[0].item, 'Silver coin sale');
    expect(rows[1].numberLabel, '2 / R');
    expect(rows[1].item, 'G-Chain sale');
    expect(rows[2].name, '');
    expect(rows[2].item, 'Mala sale');
  });

  test('names and items learned from earlier registers', () {
    expect(cleanName('Pintuai'), 'Pintu Ji');
    expect(cleanName('neeraj ji'), 'Neeraj Ji');
    expect(cleanName('Neerej Ji', known: ['Neeraj Ji']), 'Neeraj Ji');
    expect(cleanItem('Mola Sale'), 'Mala sale');
    expect(cleanItem('Kundan set'), 'Kundan set'); // unknown: kept
    expect(cleanItem('Kundan sel', known: ['Kundan set']), 'Kundan set');
  });

  test('registers are saved per day and give a vocabulary', () async {
    final book = SalesRegisterBook(
      MemoryStore(),
      clock: () => DateTime(2026, 11, 1),
    );
    expect(book.today, '2026-11-01');
    var r = book.byDate(book.today);
    expect(r.entries, isEmpty);
    expect(r.nextNumber, 1);
    r = r.copyWith(
      entries: const [
        SalesEntry(no: 1, type: 'N', name: 'Isha Ji', item: 'Silver coin sale'),
        SalesEntry(no: 2, name: 'Unchecked', item: 'X', checked: false),
      ],
    );
    await book.save(r);
    final back = book.byDate('2026-11-01');
    expect(back.entries.length, 2);
    expect(back.nextNumber, 3);
    expect(back.unchecked, 1);
    expect(back.dateLabel, '1 Nov 2026');
    expect(book.vocabulary().names, ['Isha Ji']);
  });
}

Future<void> loadAppFonts() async {
  final loader = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/Inter_400Regular.ttf').readAsBytesSync(),
        ),
      ),
    )
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/Inter_600SemiBold.ttf').readAsBytesSync(),
        ),
      ),
    );
  await loader.load();
}

class FakeOcr implements OcrService {
  FakeOcr(this.page);
  final OcrPage page;
  @override
  String get engineName => 'fake';
  @override
  bool get handlesRotation => true;
  @override
  bool get needsEnhancement => false;
  @override
  Future<String> recognize(Uint8List imageBytes) async => '';
  @override
  Future<OcrPage> recognizeLayout(Uint8List imageBytes) async => page;
  @override
  Future<void> dispose() async {}
}
