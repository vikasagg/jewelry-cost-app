import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/stock/stock_import.dart';
import 'package:jewellery_cost/ui/screens/stock/stock_items_screen.dart';
import 'package:jewellery_cost/ui/theme.dart';

/// A minimal .xlsx: shared strings and one sheet, like the shop's export.
Uint8List xlsx(List<List<Object?>> rows) {
  final strings = <String>[];
  String col(int i) =>
      String.fromCharCode(65 + i % 26).padLeft(i < 26 ? 1 : 2, 'A');
  final sheet = StringBuffer('<worksheet><sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      final ref = '${col(c)}${r + 1}';
      if (v == null) continue;
      if (v is num) {
        sheet.write('<c r="$ref"><v>$v</v></c>');
      } else {
        strings.add('$v');
        sheet.write('<c r="$ref" t="s"><v>${strings.length - 1}</v></c>');
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  final ss = StringBuffer('<sst>');
  for (final s in strings) {
    ss.write('<si><t>${const HtmlEscape().convert(s)}</t></si>');
  }
  ss.write('</sst>');
  final a = Archive()
    ..add(ArchiveFile.string('xl/sharedStrings.xml', ss.toString()))
    ..add(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet.toString()));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

final header = [
  'Tag No',
  'Item Name',
  'Date',
  'Pc',
  'Gr.Wt',
  'N.Wt',
  'Dia Wt',
  'Stn.Wt',
  'Gold Wt',
  'Design',
  'HM',
  'Lbr/Gm',
  'Mrp',
  'Supplier',
  'Dia Item',
  'Dia Wt',
  'Rate',
  'Dia Value',
  'Stn Wt',
];

void main() {
  test('reads the stock export: Tag No unique, both Dia Wt columns', () {
    final e = parseStockExport(
      xlsx([
        header,
        [
          'DBG51   ',
          'DIA. BANGLE',
          45044,
          2,
          68.27,
          68.27,
          11.56,
          null,
          65.958,
          '',
          'Y',
          750,
          55538,
          'vm ',
          'DIAMOND',
          11.56,
          375,
          4335.0000000001,
          null,
        ],
        [
          'ch1619',
          'CHAIN',
          null,
          1,
          10.5,
          10.2,
          null,
          0.3,
          10.2,
          'C89',
          '',
          650,
          null,
          '',
          '',
          null,
          null,
          null,
          0.3,
        ],
        ['', 'NO TAG', null, 1],
        ['DBG51', 'DIA. BANGLE', null, 2, 68.3],
      ]),
    );
    expect(e.items.length, 2);
    expect(e.duplicateTags, ['DBG51']); // last row kept
    expect(e.skipped, 1);
    final ch = e.items.firstWhere((i) => i['tag_no'] == 'CH1619');
    expect(ch['gross_wt'], 10.5);
    expect(ch['stone_wt'], 0.3);
    expect(ch['stn_detail_wt'], 0.3);
    expect(ch['supplier_name'], '');
    expect(e.withoutSupplier, 2); // DBG51's last row has no supplier
    final first = parseStockExport(
      xlsx([
        header,
        [
          'DBG51 ',
          'DIA. BANGLE',
          45044,
          2,
          68.27,
          68.27,
          11.56,
          null,
          65.958,
          '',
          'Y',
          750,
          55538,
          'vm ',
          'DIAMOND',
          11.56,
          375,
          4335.0000000001,
          null,
        ],
      ]),
    ).items.single;
    expect(first['tag_no'], 'DBG51');
    expect(first['entry_date'], '2023-04-28');
    expect(first['hallmark'], true);
    expect(first['dia_wt'], 11.56);
    expect(first['dia_detail_wt'], 11.56);
    expect(first['dia_value'], 4335);
    expect(first['supplier_name'], 'VM');
  });

  test('a file without a Tag No column is refused', () {
    expect(
      () => parseStockExport(
        xlsx([
          ['Name', 'Weight'],
          ['x', 1],
        ]),
      ),
      throwsFormatException,
    );
  });

  testWidgets('Stock items: search and import with a PIN', (t) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final stored = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? lastImport;
    final pc = MockClient((req) async {
      http.Response ok(Object b) => http.Response.bytes(
        utf8.encode(jsonEncode(b)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final p = req.url.path;
      if (p == '/api/damiyaas/stock-import') {
        lastImport =
            jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
        if (lastImport!['pin'] != '2222') {
          return http.Response('{"message":"Incorrect PIN"}', 401);
        }
        var created = 0;
        for (final i
            in (lastImport!['items'] as List).cast<Map<String, dynamic>>()) {
          if (stored.containsKey(i['tag_no'])) continue;
          stored[i['tag_no'] as String] = i;
          created++;
        }
        return ok({'created': created, 'updated': 0, 'suppliers': 1});
      }
      if (p == '/api/collections/stock_items/records') {
        return ok({
          'totalItems': stored.length,
          'items': stored.values.toList(),
        });
      }
      return ok({'items': [], 'totalPages': 1});
    });
    final state = AppState(
      MemoryStore()..put('stock_server_url', 'http://pc:8090'),
      httpClient: pc,
    );
    final file = xlsx([
      header,
      [
        'DBG1',
        'DIA. BANGLE',
        null,
        2,
        28.06,
        27.5,
        2.82,
        null,
        27.5,
        '',
        '',
        650,
        17872,
        'REGULAR 26 IJ',
        'DIAMOND',
        2.82,
        0,
        0,
        null,
      ],
    ]);
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: StockItemsScreen(pickExport: () async => file),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('0 items on the shop PC'), findsOneWidget);

    await t.tap(find.byKey(const Key('importStockExport')));
    await t.pumpAndSettle();
    expect(
      find.text('1 items (by Tag No) · 1 suppliers · 0 without supplier'),
      findsOneWidget,
    );
    await t.enterText(find.byKey(const Key('importName')), 'Tanish');
    await t.enterText(find.byKey(const Key('importPin')), '2222');
    await t.tap(find.byKey(const Key('importOk')));
    await t.pumpAndSettle();
    expect(lastImport!['name'], 'Tanish');
    expect(find.textContaining('Imported: 1 new'), findsOneWidget);
    expect(find.text('1 items on the shop PC'), findsOneWidget);

    await t.tap(find.byKey(const Key('stockItem_DBG1')));
    await t.pumpAndSettle();
    expect(find.text('REGULAR 26 IJ'), findsOneWidget);
    expect(find.text('2.82 ct'), findsOneWidget);
  });
}
