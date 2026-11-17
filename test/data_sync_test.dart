import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/billing/bill.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/models/gold_rates.dart';
import 'package:jewellery_cost/models/jewellery_input.dart';
import 'package:jewellery_cost/models/purity.dart';
import 'package:jewellery_cost/reports/sales_register.dart';

/// An in-memory stand-in for PocketBase on the shop PC: generic records
/// (by `key`), photo files, the bill counter, and empty stock tables.
class FakeShopPc {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  final files = <String, Uint8List>{};
  var _seq = 0, _ids = 0;
  var up = true;
  var counter = 0;

  String _stamp() => '2026-11-17 10:00:${(_seq++).toString().padLeft(6, '0')}Z';

  http.Response _ok(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  /// Photo bytes from a multipart body (one file field).
  Uint8List? _filePart(http.Request req) {
    final ct = req.headers['content-type'] ?? '';
    final b = RegExp(r'boundary=(.+)$').firstMatch(ct)?.group(1);
    if (b == null) return null;
    final bytes = req.bodyBytes;
    final text = latin1.decode(bytes);
    final head = text.indexOf('filename=');
    if (head < 0) return Uint8List(0); // photo cleared
    final start = text.indexOf('\r\n\r\n', head) + 4;
    final end = text.indexOf('\r\n--$b', start);
    return Uint8List.fromList(bytes.sublist(start, end));
  }

  late final client = MockClient((req) async {
    if (!up) throw http.ClientException('unreachable');
    final p = req.url.path;
    if (p == '/api/health') return _ok({});
    if (p == '/api/damiyaas/pin/status') return _ok({'items': []});
    if (p == '/api/damiyaas/counter') {
      final min = (jsonDecode(req.body) as Map)['min'] as int;
      counter = counter + 1 > min ? counter + 1 : min;
      return _ok({'value': counter});
    }
    if (p.startsWith('/api/files/')) {
      final f = files[p.split('/').last];
      return f == null ? http.Response('', 404) : http.Response.bytes(f, 200);
    }
    final m = RegExp(r'^/api/collections/(\w+)/records/?(\w*)$').firstMatch(p);
    if (m == null) return http.Response('{}', 404);
    final table = tables.putIfAbsent(m.group(1)!, () => {});
    final id = m.group(2)!;
    if (req.method == 'GET') {
      var items = table.values.toList()
        ..sort((a, b) => (a['updated'] as String).compareTo(b['updated']));
      final f = req.url.queryParameters['filter'] ?? '';
      final key = RegExp(r'key="([^"]*)"').firstMatch(f)?.group(1);
      final since = RegExp(r'updated>="([^"]*)"').firstMatch(f)?.group(1);
      if (key != null) items = items.where((r) => r['key'] == key).toList();
      if (since != null) {
        items = items
            .where((r) => (r['updated'] as String).compareTo(since) >= 0)
            .toList();
      }
      return _ok({'items': items, 'totalPages': 1});
    }
    if (req.method == 'POST') {
      final body =
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      if (table.values.any((r) => r['key'] == body['key'])) {
        return http.Response('{"message":"key not unique"}', 400);
      }
      final nid = 'r${_ids++}';
      table[nid] = {...body, 'id': nid, 'photo': '', 'updated': _stamp()};
      return _ok(table[nid]!);
    }
    if (req.method == 'PATCH') {
      final r = table[id];
      if (r == null) return http.Response('{}', 404);
      final photo = _filePart(req);
      if (photo != null) {
        if (photo.isEmpty) {
          r['photo'] = '';
        } else {
          final name = '${id}_$_seq.jpg';
          files[name] = photo;
          r['photo'] = name;
        }
      } else {
        r.addAll(
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>,
        );
      }
      r['updated'] = _stamp();
      return _ok(r);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  test(
    'everything is saved on the shop PC and reaches another phone',
    () async {
      final pc = FakeShopPc();
      DateTime clock() => DateTime(2026, 11, 17, 11);
      AppState phone() => AppState(
        MemoryStore()..put('stock_server_url', 'http://pc:8090'),
        clock: clock,
        httpClient: pc.client,
      );
      final a = phone(), b = phone();

      // Phone A records a bit of everything (the PC is not set up yet for B).
      final rates = GoldRates.fromBase24(
        perGram24: 13000,
        updatedAt: clock(),
        quotedPerGrams: 10,
      );
      await a.saveRates(rates);
      const input = JewelleryInput(
        tagNumber: 'CH1619',
        itemName: 'Chain',
        purity: Purity.k22,
        goldWeight: 10,
        makingMethod: MakingMethod.percentOfGold,
        makingValue: 16,
        gst: GstConfig(ratePercent: 3),
      );
      final res = a.engine.calculate(input, rates.perGram).result!;
      final photo = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 6)),
      );
      final rec = await a.saveCalculation(
        input: input,
        ratesSnapshot: rates,
        result: res,
        image: photo,
      );
      final bill = await a.saveBill(
        items: [rec],
        customerName: 'Asha Verma',
        phone: '9876543210',
        address: 'Sector 14',
        payment: PaymentMode.upi,
      );
      expect(bill.billNo, 'DJB-0001'); // from the PC
      await a.sales.save(
        const SalesRegister(
          date: '2026-11-17',
          entries: [SalesEntry(no: 1, name: 'Isha Ji', item: 'Coin')],
        ),
      );
      await a.metalPrices.save(
        '2026-11-17',
        gold24Per10g: 130000,
        silverPerKg: 160000,
      );
      await a.stockSync.syncNow();
      expect(a.stockSync.lastError, isNull);

      // On the PC, with readable columns.
      final est = pc.tables['estimates']!.values.single;
      expect(est['tag_number'], 'CH1619');
      expect(est['purity'], '22K');
      expect(est['photo'], isNotEmpty);
      expect(pc.tables['bills']!.values.single['customer_name'], 'Asha Verma');
      expect(pc.tables['sales_registers']!.values.single['line_count'], 1);
      expect(pc.tables['metal_prices']!.values.single['silver_per_kg'], 160000);
      expect(
        pc.tables['settings']!.values.map((r) => r['key']),
        containsAll(['gold_rates', 'bill_counter']),
      );

      // Phone B gets all of it, photo included.
      await b.stockSync.syncNow();
      expect(b.rates!.perGram[Purity.k24], 13000);
      expect(b.history.all().single.input.tagNumber, 'CH1619');
      expect(b.imageFor(rec.id), photo);
      expect(b.billFor(rec.id)!.customerName, 'Asha Verma');
      expect(b.sales.byDate('2026-11-17').entries.single.name, 'Isha Ji');
      expect(b.metalPrices.byDate('2026-11-17')!.gold24Per10g, 130000);
      // B's next bill does not repeat A's number.
      final bill2 = await b.saveBill(
        items: b.history.all(),
        customerName: 'Second',
        phone: '',
        address: '',
        payment: PaymentMode.cash,
      );
      expect(bill2.billNo, 'DJB-0002');

      // B deletes the estimate; A follows on its next sync.
      await b.deleteCalculation(rec.id);
      await b.stockSync.syncNow();
      expect(est['deleted'], isTrue);
      await a.stockSync.syncNow();
      expect(a.history.all(), isEmpty);
      expect(a.imageFor(rec.id), isNull);
    },
  );

  test('offline: saved on the phone, sent when the PC is back', () async {
    final pc = FakeShopPc()..up = false;
    final a = AppState(
      MemoryStore()..put('stock_server_url', 'http://pc:8090'),
      clock: () => DateTime(2026, 11, 17),
      httpClient: pc.client,
    );
    await a.metalPrices.save('2026-11-17', gold24Per10g: 129000);
    final bill = await a.saveBill(
      items: const [],
      customerName: 'Walk-in',
      phone: '',
      address: '',
      payment: PaymentMode.cash,
    );
    expect(bill.billNo, 'DJB-0001'); // phone's own counter while offline
    await a.stockSync.syncNow();
    expect(a.stockSync.state.name, 'offline');

    pc.up = true;
    await a.stockSync.syncNow();
    expect(a.stockSync.state.name, 'synced');
    expect(pc.tables['metal_prices']!.values.single['gold24_per_10g'], 129000);
    expect(pc.tables['bills']!.values.single['bill_no'], 'DJB-0001');
  });
}
