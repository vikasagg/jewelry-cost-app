import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/stock/stock_lookup.dart';
import 'package:jewellery_cost/ui/screens/details_form_screen.dart';
import 'package:jewellery_cost/ui/theme.dart';

/// Records as the shop PC returns them (from the stock export).
final dbg51 = <String, dynamic>{
  'tag_no': 'DBG51',
  'item_name': 'DIA. BANGLE',
  'pcs': 2,
  'gross_wt': 68.27,
  'net_wt': 68.27,
  'dia_wt': 11.56,
  'gold_wt': 65.958,
  'labour_per_gm': 750,
  'labour_rs': 0,
  'mrp': 55538,
  'supplier_name': 'VM',
  'dia_item': 'DIAMOND',
  'dia_detail_wt': 11.56,
  'dia_rate': 375,
  'dia_value': 4335,
  'stn_item': '',
  'stn_pcs': 0,
  'stn_detail_wt': 0,
  'stn_rate': 0,
  'gold_std': '',
};

final dbg91 = <String, dynamic>{
  ...dbg51,
  'tag_no': 'DBG91',
  'gross_wt': 32.88,
  'gold_wt': 26.106,
  'dia_detail_wt': 7.43,
  'dia_rate': 325,
  'labour_per_gm': 650,
  'stn_item': 'STONES',
  'stn_pcs': 56,
  'stn_detail_wt': 26.44,
  'stn_rate': 200,
  'gold_std': '22K',
};

double? rateFor(StoneKind k, String? code) {
  final n = double.tryParse(code ?? '');
  return n == null ? null : n * (k == StoneKind.stone ? 1 : 100);
}

void main() {
  const current = JewelleryInput(
    purity: Purity.k18,
    gst: GstConfig(ratePercent: 3),
    wastagePercent: 2,
  );

  test('weights, diamond (rate as tag code) and labour per gram', () {
    final i = inputFromStockItem(dbg51, current, rateFor: rateFor);
    expect(i.tagNumber, 'DBG51');
    expect(i.itemName, 'DIA. BANGLE');
    expect(i.grossWeight, 68.27);
    expect(i.goldWeight, 65.958); // Gold Wt, not N.Wt
    expect(i.purity, Purity.k18); // no Gold Std: kept
    expect(i.stones.single.kind, StoneKind.diamond);
    expect(i.stones.single.weightCt, 11.56);
    expect(i.stones.single.ratePerCt, 37500); // code 375 × 100
    expect(i.makingMethod, MakingMethod.perGram);
    expect(i.makingValue, 750);
    expect(i.gst.ratePercent, 3); // kept
    expect(i.wastagePercent, 2); // kept
  });

  test('stones per piece, purity from Gold Std, polki, fixed labour', () {
    final i = inputFromStockItem(dbg91, current, rateFor: rateFor);
    expect(i.purity, Purity.k22);
    expect(i.stones.map((s) => s.kind), [StoneKind.diamond, StoneKind.stone]);
    final stone = i.stones.last;
    expect(stone.weightCt, 56); // pieces
    expect(stone.ratePerCt, 200);
    // No piece count but a value (weight × rate): one piece at that value.
    final byWeight = inputFromStockItem(
      {...dbg91, 'stn_pcs': 0, 'stn_value': 5288},
      current,
      rateFor: rateFor,
    ).stones.last;
    expect(byWeight.weightCt, 1);
    expect(byWeight.ratePerCt, 5288);

    final p = inputFromStockItem(
      {
        ...dbg51,
        'dia_wt': 0,
        'dia_detail_wt': 0,
        'stn_item': 'POLKI',
        'stn_detail_wt': 3.5,
        'stn_rate': 700,
        'labour_per_gm': 0,
        'labour_rs': 900,
      },
      current,
      rateFor: rateFor,
    );
    expect(p.stones.single.kind, StoneKind.polki);
    expect(p.stones.single.weightCt, 3.5);
    expect(p.stones.single.ratePerCt, 70000);
    expect(p.makingMethod, MakingMethod.fixed);
    expect(p.makingValue, 900);

    expect(purityFromStd('18 KT'), Purity.k18);
    expect(purityFromStd('916'), Purity.k22);
    expect(purityFromStd(''), isNull);
  });

  testWidgets('Manual entry: Enter on the tag number fills the form', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final asked = <String>[];
    final pc = MockClient((req) async {
      final f = req.url.queryParameters['filter'] ?? '';
      if (req.url.path == '/api/collections/stock_items/records') {
        asked.add(f);
        final items = f.contains('"DBG91"') ? [dbg91] : [];
        return http.Response.bytes(
          utf8.encode(jsonEncode({'items': items})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{"items":[],"totalPages":1}', 200);
    });
    final state = AppState(
      MemoryStore()..put('stock_server_url', 'http://pc:8090'),
      httpClient: pc,
    );
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: const DetailsFormScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    String text(String key) =>
        (t.widget(find.byKey(Key(key))) as TextField).controller!.text;

    // Unknown tag: nothing changes.
    await t.enterText(find.byKey(const Key('tagNumber')), 'xx1');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(find.text('Tag XX1 is not in the shop stock'), findsOneWidget);

    await t.enterText(find.byKey(const Key('tagNumber')), 'dbg91');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(asked.last, 'tag_no="DBG91"');
    expect(text('tagNumber'), 'DBG91');
    expect(text('grossWeight'), '32.88');
    expect(text('goldWeight'), '26.106');
    expect(text('makingValue'), '650');
    expect(text('stone.0.weight'), '7.43');
    expect(text('stone.0.rate'), '32500');
    expect(text('stone.1.weight'), '56');
    expect(text('stone.1.rate'), '200');
    expect(find.textContaining('Filled from stock: DBG91'), findsOneWidget);
  });

  testWidgets('Manual entry without the shop PC says how to connect', (
    t,
  ) async {
    final state = AppState(MemoryStore());
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: const DetailsFormScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tagNumber')), 'DBG51');
    await t.tap(find.byKey(const Key('tagLookup')));
    await t.pumpAndSettle();
    expect(find.textContaining('Connect the shop PC'), findsOneWidget);
  });
}
