import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/stock/stock_book.dart';
import 'package:jewellery_cost/stock/stock_models.dart';
import 'package:jewellery_cost/stock/stock_sync.dart';

/// A tiny in-memory PocketBase: staff and stock_days records.
class FakePocketBase {
  final days = <String, Map<String, dynamic>>{}; // id -> record
  var up = true;
  var nextId = 0;
  final staff = [
    {'name': 'Anil', 'phone': '7678405443'},
    {'name': 'Bhavna', 'phone': '9205348300'},
    {'name': 'Tanish', 'phone': '9667725005'},
  ];

  late final client = MockClient((req) async {
    if (!up) throw http.ClientException('unreachable');
    final p = req.url.path;
    http.Response ok(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    if (p == '/api/health') return ok({'code': 200});
    if (p == '/api/collections/staff/records') {
      return ok({'items': staff, 'totalPages': 1});
    }
    const base = '/api/collections/stock_days/records';
    if (p == base && req.method == 'GET') {
      final f = req.url.queryParameters['filter'];
      var items = days.values.toList();
      if (f != null) {
        final date = RegExp(r"date='([^']+)'").firstMatch(f)!.group(1);
        items = items.where((r) => r['date'] == date).toList();
      }
      return ok({'items': items, 'totalPages': 1});
    }
    if (p == base && req.method == 'POST') {
      final body =
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      if (days.values.any((r) => r['date'] == body['date'])) {
        return http.Response('{"message":"not unique"}', 400);
      }
      final id = 'r${nextId++}';
      days[id] = {...body, 'id': id};
      return ok(days[id]!);
    }
    if (p.startsWith('$base/') && req.method == 'PATCH') {
      final id = p.substring(base.length + 1);
      if (!days.containsKey(id)) return http.Response('{}', 404);
      days[id] = {
        ...days[id]!,
        ...jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>,
        'id': id,
      };
      return ok(days[id]!);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  test('normalise server address', () {
    expect(
      StockSync.normalise('192.168.1.10:8090'),
      'http://192.168.1.10:8090',
    );
    expect(
      StockSync.normalise(' http://192.168.1.10:8090/ '),
      'http://192.168.1.10:8090',
    );
    expect(StockSync.normalise(''), '');
  });

  test('two phones share counts and staff through the shop PC', () async {
    final pc = FakePocketBase();
    DateTime clock() => DateTime(2026, 10, 19, 11);
    final storeA = MemoryStore(), storeB = MemoryStore();
    final bookA = StockBook(storeA, clock: clock);
    final bookB = StockBook(storeB, clock: clock);
    final a = StockSync(storeA, bookA, client: pc.client, clock: clock);
    final b = StockSync(storeB, bookB, client: pc.client, clock: clock);

    expect(await a.test('http://pc:8090'), isNull);
    await storeA.put('stock_server_url', 'http://pc:8090');
    await storeB.put('stock_server_url', 'http://pc:8090');

    // Phone A counts LGR = 5.
    var day = await bookA.open('2026-10-19');
    day = await bookA.setEmployee(day, 'Anil');
    day = await bookA.setCount(day, 'LGR', 5);
    expect(bookA.unsentDates, ['2026-10-19']);
    await a.syncNow();
    expect(a.lastError, isNull);
    expect(a.state, SyncState.synced);
    expect(bookA.unsentDates, isEmpty);
    expect(pc.days.length, 1);
    expect(pc.days.values.single['employee'], 'Anil');
    expect(a.staff.map((s) => s.name), ['Anil', 'Bhavna', 'Tanish']);

    // Phone B receives it, adds GGR = 2 and sends it back.
    await b.syncNow();
    var dayB = bookB.byDate('2026-10-19')!;
    expect(dayB.counts['LGR'], 5);
    expect(dayB.employee, 'Anil');
    dayB = await bookB.setCount(dayB, 'GGR', 2);
    await b.syncNow();
    expect(pc.days.length, 1); // same record updated, not duplicated

    await a.syncNow();
    expect(bookA.byDate('2026-10-19')!.counts, {'LGR': 5, 'GGR': 2});
  });

  test('offline: changes wait on the phone and go up later', () async {
    final pc = FakePocketBase()..up = false;
    final store = MemoryStore();
    final book = StockBook(store, clock: () => DateTime(2026, 10, 19));
    final sync = StockSync(store, book, client: pc.client);
    await store.put('stock_server_url', 'http://pc:8090');

    var day = await book.open('2026-10-19');
    day = await book.setCount(day, 'LGR', 3);
    await sync.syncNow();
    expect(sync.state, SyncState.offline);
    expect(sync.unsent, 1);

    pc.up = true;
    await sync.syncNow();
    expect(sync.state, SyncState.synced);
    expect(sync.unsent, 0);
    final saved = DailyStock.fromJson(
      (pc.days.values.single['data'] as Map).cast<String, dynamic>(),
    );
    expect(saved.counts['LGR'], 3);
  });

  test('a day changed here is not overwritten by the server copy', () async {
    final store = MemoryStore();
    final book = StockBook(store, clock: () => DateTime(2026, 10, 19));
    var day = await book.open('2026-10-19');
    day = await book.setCount(day, 'LGR', 7);
    final remote = day.copyWith(counts: {'LGR': 1});
    expect(await book.applyRemote(remote), isFalse);
    expect(book.byDate('2026-10-19')!.counts['LGR'], 7);
    await book.markSent('2026-10-19', book.changeMark('2026-10-19'));
    expect(await book.applyRemote(remote), isTrue);
    expect(book.byDate('2026-10-19')!.counts['LGR'], 1);
  });

  test('auto-save without changes does not resend the day', () async {
    final store = MemoryStore();
    var t = DateTime(2026, 10, 19, 10);
    final book = StockBook(store, clock: () => t);
    final day = await book.open('2026-10-19');
    await book.markSent(day.date, book.changeMark(day.date));
    t = t.add(const Duration(seconds: 3));
    await book.autosave(book.byDate(day.date)!);
    t = t.add(const Duration(seconds: 3));
    await book.autosave(book.byDate(day.date)!);
    expect(book.unsentDates, isEmpty);
    // A real change is sent.
    await book.autosave(book.byDate(day.date)!.copyWith(note: 'checked'));
    expect(book.unsentDates, [day.date]);
  });
}
