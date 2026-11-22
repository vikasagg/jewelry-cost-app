import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/key_value_store.dart';

/// A piece of stock as Swarn-OS (the shop's inventory system) prices it at
/// today's approved rate (`GET /api/items/code/{tag}`).
class SwarnItem {
  SwarnItem(this.json);

  final Map<String, dynamic> json;

  static double? _num(Object? v) => v is num
      ? v.toDouble()
      : v is String
      ? double.tryParse(v)
      : null;

  Map<String, dynamic> get _breakdown =>
      (json['price_breakdown'] as Map?)?.cast<String, dynamic>() ?? const {};

  String get tag => '${json['tag_code'] ?? ''}';
  String get name => '${json['name'] ?? json['category_name'] ?? ''}';
  String get category => '${json['category_name'] ?? ''}';
  String get metal => '${json['metal'] ?? ''}';
  String get purity => '${json['purity_code'] ?? ''}';
  String get status => '${json['status'] ?? ''}';
  String get huid => '${json['huid'] ?? ''}';
  int get quantity => (json['quantity'] as num?)?.toInt() ?? 1;
  double? get grossWt => _num(json['gross_wt']);
  double? get stoneWt => _num(json['stone_wt']);
  double? get netWt => _num(json['net_wt']);
  double? get stoneCarat => _num(json['stone_carat']);

  /// Rate per gram for this purity, as used for the price.
  double? get rate => _num(_breakdown['rate']);
  double? get metalValue => _num(_breakdown['metal_value']);
  double? get wastageValue => _num(_breakdown['wastage_value']);
  double? get makingValue => _num(_breakdown['making_value']);
  double? get stoneValue =>
      _num(_breakdown['stone_value']) ?? _num(json['stone_value']);
  double? get discount => _num(_breakdown['discount']);
  double? get taxable => _num(_breakdown['taxable']);
  double? get gstPct => _num(_breakdown['gst_pct']) ?? _num(json['gst_pct']);
  double? get gst => _num(_breakdown['gst']);

  /// Price including GST.
  double? get price => _num(json['price']) ?? _num(_breakdown['total']);

  bool get inStock => status.isEmpty || status == 'IN_STOCK';
}

class SwarnException implements Exception {
  SwarnException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Connection to Swarn-OS: server address, shop code and a login. Kept on
/// this phone only (not sent to the shop PC's PocketBase).
class SwarnOs {
  SwarnOs(this._store, {http.Client? client})
    : _client = client ?? http.Client();

  final KeyValueStore _store;
  final http.Client _client;
  String? _token;

  static const defaultUrl = 'http://localhost:8080';
  static const _kUrl = 'swarn_url',
      _kShop = 'swarn_shop',
      _kUser = 'swarn_user',
      _kPassword = 'swarn_password';

  String get url => _store.get(_kUrl) ?? defaultUrl;
  String get shop => _store.get(_kShop) ?? '';
  String get user => _store.get(_kUser) ?? '';
  String get password => _store.get(_kPassword) ?? '';
  bool get configured => shop.isNotEmpty && user.isNotEmpty;

  /// "192.168.1.10:8080" → "http://192.168.1.10:8080".
  static String normalizeUrl(String text) {
    var t = text.trim();
    if (t.isEmpty) return defaultUrl;
    if (!t.contains('://')) t = 'http://$t';
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  Future<void> save({
    required String url,
    required String shop,
    required String user,
    required String password,
  }) async {
    await _store.put(_kUrl, normalizeUrl(url));
    await _store.put(_kShop, shop.trim());
    await _store.put(_kUser, user.trim());
    await _store.put(_kPassword, password);
    _token = null;
  }

  Uri _uri(String path, [String? base]) =>
      Uri.parse('${normalizeUrl(base ?? url)}$path');

  static String _message(http.Response r, String fallback) {
    try {
      final j = jsonDecode(r.body) as Map;
      final m = j['error'] ?? j['message'];
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return fallback;
  }

  /// Signs in and returns the shop's name.
  Future<String> login({
    String? url,
    String? shop,
    String? user,
    String? password,
  }) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            _uri('/api/auth/login', url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'shop': shop ?? this.shop,
              'username': user ?? this.user,
              'password': password ?? this.password,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw SwarnException(
        'Swarn-OS not reachable at ${normalizeUrl(url ?? this.url)}',
      );
    }
    if (r.statusCode != 200) {
      throw SwarnException(
        _message(
          r,
          'Login failed (${r.statusCode}): check shop, user and password',
        ),
      );
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    _token = j['token'] as String?;
    return '${(j['shop'] as Map?)?['name'] ?? shop ?? this.shop}';
  }

  /// The piece with this tag at today's price, or null if Swarn-OS does not
  /// know the tag.
  Future<SwarnItem?> itemByTag(String tag) async {
    if (!configured) {
      throw SwarnException('Set up Swarn-OS first (gear icon)');
    }
    final code = tag.trim().toUpperCase();
    Future<http.Response> get() async {
      try {
        return await _client
            .get(
              _uri('/api/items/code/${Uri.encodeComponent(code)}'),
              headers: {'Authorization': 'Bearer $_token'},
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        throw SwarnException('Swarn-OS not reachable at $url');
      }
    }

    if (_token == null) await login();
    var r = await get();
    if (r.statusCode == 401) {
      await login();
      r = await get();
    }
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw SwarnException(_message(r, 'Swarn-OS error ${r.statusCode}'));
    }
    return SwarnItem((jsonDecode(r.body) as Map).cast<String, dynamic>());
  }
}
