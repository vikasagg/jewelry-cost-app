import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jewellery_cost/app_state.dart';
import 'package:jewellery_cost/data/key_value_store.dart';
import 'package:jewellery_cost/swarn/swarn_os.dart';
import 'package:jewellery_cost/ui/screens/fetch_price_screen.dart';
import 'package:jewellery_cost/ui/theme.dart';

/// T000024 from the Swarn-OS demo shop, as `GET /api/items/code/T000024`
/// returns it (fields the app reads).
const bangle = {
  'tag_code': 'T000024',
  'category_name': 'Diamond Bangle',
  'gst_pct': 3.0,
  'name': 'Diamond Bangle',
  'metal': 'GOLD',
  'purity_code': '18K',
  'gross_wt': 16.8,
  'stone_wt': 0.24,
  'net_wt': 16.56,
  'quantity': 1,
  'huid': 'HU5916',
  'status': 'IN_STOCK',
  'stone_value': 90000.0,
  'stone_carat': 1.2,
  'stone_type': 'DIAMOND',
  'price': 215508.96,
  'price_breakdown': {
    'rate': 5700.0,
    'metal_value': 94392.0,
    'wastage_value': 0.0,
    'making_value': 24840.0,
    'stone_value': 90000.0,
    'discount': 0.0,
    'taxable': 209232.0,
    'gst_pct': 3.0,
    'gst': 6276.96,
    'total': 215508.96,
  },
};

/// A fake Swarn-OS: shop demo, user sales / demo123; the token expires
/// after [expireAfter] item lookups.
MockClient fakeSwarn(List<String> log, {int expireAfter = 99}) {
  var token = 0, lookups = 0;
  return MockClient((req) async {
    log.add('${req.method} ${req.url}');
    if (req.url.path == '/api/auth/login') {
      final b = jsonDecode(req.body) as Map;
      if (b['shop'] != 'demo' ||
          b['username'] != 'sales' ||
          b['password'] != 'demo123') {
        return http.Response(
          jsonEncode({'error': 'Wrong shop code, username or password.'}),
          401,
        );
      }
      token++;
      return http.Response(
        jsonEncode({
          'token': 'tok$token',
          'shop': {'code': 'demo', 'name': 'Demo Jewellers'},
        }),
        200,
      );
    }
    if (req.headers['Authorization'] != 'Bearer tok$token' ||
        lookups++ >= expireAfter) {
      lookups = 0;
      token++; // old token no longer valid
      return http.Response(jsonEncode({'error': 'Sign in again'}), 401);
    }
    final code = req.url.pathSegments.last;
    if (code == 'T000024') return http.Response(jsonEncode(bangle), 200);
    return http.Response(jsonEncode({'error': 'No item with tag $code'}), 404);
  });
}

void main() {
  test(
    'logs in, fetches by tag, signs in again when the token expires',
    () async {
      final log = <String>[];
      final s = SwarnOs(MemoryStore(), client: fakeSwarn(log, expireAfter: 1));
      await s.save(
        url: '192.168.1.10:8080/',
        shop: 'demo',
        user: 'sales',
        password: 'demo123',
      );
      expect(s.url, 'http://192.168.1.10:8080');
      final item = (await s.itemByTag(' t000024 '))!;
      expect(item.name, 'Diamond Bangle');
      expect(item.purity, '18K');
      expect(item.netWt, 16.56);
      expect(item.makingValue, 24840);
      expect(item.price, 215508.96);
      expect(log, [
        'POST http://192.168.1.10:8080/api/auth/login',
        'GET http://192.168.1.10:8080/api/items/code/T000024',
      ]);
      // Second lookup: token expired → one new login, then the answer.
      expect(await s.itemByTag('NOPE'), isNull);
      expect(log.where((l) => l.contains('login')), hasLength(2));
    },
  );

  test('wrong password and unreachable server give plain messages', () async {
    final s = SwarnOs(MemoryStore(), client: fakeSwarn([]));
    await expectLater(
      s.login(shop: 'demo', user: 'sales', password: 'x'),
      throwsA(
        isA<SwarnException>().having(
          (e) => e.message,
          'message',
          'Wrong shop code, username or password.',
        ),
      ),
    );
    final down = SwarnOs(
      MemoryStore(),
      client: MockClient((_) async => throw Exception('refused')),
    );
    await down.save(url: '', shop: 'demo', user: 'sales', password: 'p');
    await expectLater(
      down.itemByTag('T1'),
      throwsA(
        isA<SwarnException>().having(
          (e) => e.message,
          'message',
          'Swarn-OS not reachable at http://localhost:8080',
        ),
      ),
    );
  });

  testWidgets('Fetch Price: set up, then tag → price', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final state = AppState(MemoryStore(), httpClient: fakeSwarn([]));
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(theme: buildTheme(), home: const FetchPriceScreen()),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('fetchTag')), 't000024');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    // Not set up yet: the connection dialog opens first.
    expect(find.byKey(const Key('swarnUrl')), findsOneWidget);
    await t.enterText(find.byKey(const Key('swarnUrl')), 'localhost:8080');
    await t.enterText(find.byKey(const Key('swarnShop')), 'demo');
    await t.enterText(find.byKey(const Key('swarnUser')), 'sales');
    await t.enterText(find.byKey(const Key('swarnPassword')), 'wrong');
    await t.tap(find.byKey(const Key('swarnSave')));
    await t.pumpAndSettle();
    expect(find.text('Wrong shop code, username or password.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('swarnPassword')), 'demo123');
    await t.tap(find.byKey(const Key('swarnSave')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('swarnUrl')), findsNothing);
    expect(
      (t.widget(find.byKey(const Key('fetchedPrice'))) as Text).data,
      '₹2,15,508.96',
    );
    expect(find.text('GOLD 18K'), findsOneWidget);
    expect(find.text('16.560 g'), findsOneWidget);
    expect(find.text('₹24,840.00'), findsOneWidget); // making

    await t.enterText(find.byKey(const Key('fetchTag')), 'X9');
    await t.tap(find.byKey(const Key('fetchPriceGo')));
    await t.pumpAndSettle();
    expect(find.text('Tag X9 is not in Swarn-OS'), findsOneWidget);
    expect(find.byKey(const Key('fetchedPrice')), findsNothing);
  });
}
