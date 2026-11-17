import 'dart:convert';

import 'package:http/http.dart' as http;

import '../billing/bill.dart';
import '../data/syncing_store.dart';
import '../metals/metal_prices.dart';
import '../models/calculation_record.dart';
import '../reports/sales_register.dart';

/// One kind of data shared with the shop PC: the phone keys with
/// [prefix] (or exactly [keys]) ↔ records of PocketBase [collection],
/// found by their `key` field.
class SharedKind {
  const SharedKind(
    this.collection, {
    this.prefix = '',
    this.keys = const {},
    this.json = true,
    this.columns,
  });

  final String collection;
  final String prefix;
  final Set<String> keys;

  /// Stored as JSON (else kept as text in `data.value`).
  final bool json;

  /// Readable columns for the admin panel, from the stored data.
  final Map<String, dynamic> Function(Map<String, dynamic> data)? columns;

  bool owns(String localKey) =>
      prefix.isNotEmpty ? localKey.startsWith(prefix) : keys.contains(localKey);

  String recordKey(String localKey) =>
      prefix.isEmpty ? localKey : localKey.substring(prefix.length);

  String localKey(String recordKey) => '$prefix$recordKey';
}

/// Tag photos (`img_<id>`) are stored as the `photo` image of the matching
/// estimate.
const _photoPrefix = 'img_';

double _rupees(int paise) => paise / 100;

/// Everything the app records, apart from stock counts (StockSync).
final sharedKinds = <SharedKind>[
  SharedKind(
    'estimates',
    prefix: 'calc_',
    columns: (j) {
      final r = CalculationRecord.fromJson(j);
      return {
        'tag_number': r.input.tagNumber ?? '',
        'item': r.input.itemName ?? '',
        'purity': r.result.purity.label,
        'gross_weight': r.input.grossWeight ?? 0,
        'net_weight': r.input.goldWeight ?? 0,
        'total': _rupees(r.result.totalPaise),
        'source': r.source,
        'estimated_at': r.createdAt.toUtc().toIso8601String(),
      };
    },
  ),
  SharedKind(
    'bills',
    prefix: 'billdoc_',
    columns: (j) {
      final b = Bill.fromJson(j);
      return {
        'bill_no': b.billNo,
        'customer_name': b.customerName,
        'phone': b.phone,
        'address': b.address,
        'payment': b.payment.label,
        'items': b.items.length,
        'total': _rupees(b.totalPaise),
        'billed_at': b.createdAt.toUtc().toIso8601String(),
      };
    },
  ),
  SharedKind(
    'sales_registers',
    prefix: 'sales_register_',
    columns: (j) {
      final r = SalesRegister.fromJson(j);
      return {
        'register_date': r.date,
        'line_count': r.entries.length,
        // Expanded into sales_register_lines on the PC.
        'lines': [
          for (final e in r.entries)
            {
              'no': e.no,
              'customer_type': e.type.code,
              'name': e.name,
              'mobile': e.mobile,
              'deal': e.deal.label,
              'metal': e.metal.label,
              'item': e.item,
              'checked': e.checked,
            },
        ],
      };
    },
  ),
  SharedKind(
    'metal_prices',
    prefix: 'metal_price_',
    columns: (j) {
      final p = MetalPrice.fromJson(j);
      return {
        'price_date': p.date,
        'gold24_per_10g': p.gold24Per10g ?? 0,
        'silver_per_kg': p.silverPerKg ?? 0,
      };
    },
  ),
  const SharedKind(
    'settings',
    json: false,
    keys: {
      'gold_rates',
      'dj_tag_counter',
      'bill_counter',
      'tag_rate_multiplier',
      'tag_rate_multiplier_stone_v2',
      'tag_rate_multiplier_polki',
    },
  ),
];

/// Whether a phone key is shared with the shop PC.
bool isSharedKey(String key) =>
    key.startsWith(_photoPrefix) || sharedKinds.any((k) => k.owns(key));

class DataSyncException implements Exception {
  DataSyncException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'Server error $status';
}

/// Sends this phone's changes to the shop PC and brings in other phones'
/// changes. Changes made here win over the PC's copy until they are sent
/// (last save wins). Deletions are sent as `deleted` records.
class DataSync {
  DataSync(this._store, {this.onRemoteChange});

  final SyncingStore _store;

  /// Called after data from the PC was written here.
  final void Function()? onRemoteChange;

  static const _idPrefix = 'sync_rid_';
  static const _sincePrefix = 'sync_since_';
  static const _photoNamePrefix = 'sync_photo_';
  static const _versionKey = 'sync_version';

  /// Bumped when more data is shared: everything is sent again once.
  static const version = '1';

  /// Items the PC refused in the last round (kept on this phone).
  final rejected = <String>[];

  late http.Client _http;
  late Uri _base;

  Uri _u(String path, [Map<String, String>? q]) =>
      _base.resolve(path).replace(queryParameters: q);

  Future<Map<String, dynamic>> _json(Future<http.Response> req) async {
    final res = await req.timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DataSyncException(res.statusCode, res.body);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static const _headers = {'content-type': 'application/json; charset=utf-8'};

  SharedKind? _kindOf(String localKey) {
    for (final k in sharedKinds) {
      if (k.owns(localKey)) return k;
    }
    return null;
  }

  String _records(String c) => 'api/collections/$c/records';

  Future<String?> _findId(SharedKind kind, String key) async {
    final cached = _store.get('$_idPrefix${kind.collection}_$key');
    if (cached != null) return cached;
    final j = await _json(
      _http.get(
        _u(_records(kind.collection), {
          'filter': 'key=${jsonEncode(key)}',
          'fields': 'id',
          'perPage': '1',
        }),
      ),
    );
    final items = j['items'] as List;
    if (items.isEmpty) return null;
    final id = (items.first as Map)['id'] as String;
    await _store.putRemote('$_idPrefix${kind.collection}_$key', id);
    return id;
  }

  /// Creates or updates the record for [key]; returns its id.
  Future<String> _upsert(
    SharedKind kind,
    String key,
    Map<String, dynamic> body,
  ) async {
    Future<String> patch(String id) async =>
        (await _json(
              _http.patch(
                _u('${_records(kind.collection)}/$id'),
                headers: _headers,
                body: jsonEncode(body),
              ),
            ))['id']
            as String;
    final id = await _findId(kind, key);
    if (id != null) {
      try {
        return await patch(id);
      } on DataSyncException catch (e) {
        if (e.status != 404) rethrow;
        await _store.deleteRemote('$_idPrefix${kind.collection}_$key');
      }
    }
    try {
      final created =
          (await _json(
                _http.post(
                  _u(_records(kind.collection)),
                  headers: _headers,
                  body: jsonEncode({...body, 'key': key}),
                ),
              ))['id']
              as String;
      await _store.putRemote('$_idPrefix${kind.collection}_$key', created);
      return created;
    } on DataSyncException catch (e) {
      // Another phone created it a moment ago.
      if (e.status != 400) rethrow;
      await _store.deleteRemote('$_idPrefix${kind.collection}_$key');
      final again = await _findId(kind, key);
      if (again == null) rethrow;
      return patch(again);
    }
  }

  Future<void> _sendKey(String localKey) async {
    final mark = _store.changeMark(localKey);
    if (localKey.startsWith(_photoPrefix)) {
      await _sendPhoto(localKey.substring(_photoPrefix.length));
      await _store.markSent(localKey, mark);
      return;
    }
    final kind = _kindOf(localKey);
    if (kind == null) {
      await _store.markSent(localKey, mark);
      return;
    }
    final key = kind.recordKey(localKey);
    final raw = _store.get(localKey);
    final Map<String, dynamic> body;
    if (raw == null) {
      body = {'deleted': true, 'client_updated': _now()};
    } else {
      final data = kind.json
          ? jsonDecode(raw) as Map<String, dynamic>
          : <String, dynamic>{'value': raw};
      Map<String, dynamic> cols = const {};
      try {
        cols = kind.columns?.call(data) ?? const {};
      } catch (_) {
        // Readable columns are a convenience; the data is what matters.
      }
      body = {
        ...cols,
        'data': data,
        'deleted': false,
        'client_updated': _now(),
      };
    }
    await _upsert(kind, key, body);
    await _store.markSent(localKey, mark);
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  /// Uploads the tag photo of estimate [id] (after the estimate itself).
  Future<void> _sendPhoto(String id) async {
    final kind = sharedKinds.first; // estimates
    final b64 = _store.get('$_photoPrefix$id');
    final recordId = await _findId(kind, id);
    if (recordId == null) return; // estimate not on the PC (deleted)
    final req = http.MultipartRequest(
      'PATCH',
      _u('${_records(kind.collection)}/$recordId'),
    );
    if (b64 == null) {
      req.fields['photo'] = '';
    } else {
      req.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          base64Decode(b64),
          filename: '$id.jpg',
        ),
      );
    }
    final res = await http.Response.fromStream(
      await _http.send(req).timeout(const Duration(seconds: 30)),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DataSyncException(res.statusCode, res.body);
    }
    final name = (jsonDecode(res.body) as Map)['photo'] as String? ?? '';
    await _store.putRemote('$_photoNamePrefix$id', name);
  }

  /// Applies one record from the PC here.
  Future<bool> _apply(SharedKind kind, Map<String, dynamic> r) async {
    final key = r['key'] as String? ?? '';
    if (key.isEmpty) return false;
    final localKey = kind.localKey(key);
    await _store.putRemote(
      '$_idPrefix${kind.collection}_$key',
      r['id'] as String,
    );
    // Changed here and not sent yet: this phone's version goes up next.
    if (_store.changeMark(localKey) != null) return false;
    var changed = false;
    if (r['deleted'] == true) {
      if (_store.get(localKey) != null) {
        await _store.deleteRemote(localKey);
        changed = true;
      }
      if (kind.collection == 'estimates' &&
          _store.get('$_photoPrefix$key') != null) {
        await _store.deleteRemote('$_photoPrefix$key');
      }
      return changed;
    }
    final data = r['data'];
    if (data is! Map) return false;
    final String value;
    if (kind.json) {
      value = jsonEncode(data);
    } else {
      value = data['value']?.toString() ?? '';
      // Counters only move forward.
      if (key.endsWith('_counter')) {
        final here = int.tryParse(_store.get(localKey) ?? '') ?? 0;
        if ((int.tryParse(value) ?? 0) <= here) return false;
      }
    }
    if (_store.get(localKey) != value) {
      await _store.putRemote(localKey, value);
      changed = true;
    }
    if (kind.collection == 'estimates') {
      changed = await _receivePhoto(key, r) || changed;
    }
    return changed;
  }

  Future<bool> _receivePhoto(String id, Map<String, dynamic> r) async {
    final name = r['photo'] as String? ?? '';
    final photoKey = '$_photoPrefix$id';
    if (_store.changeMark(photoKey) != null) return false;
    if (name.isEmpty) return false;
    if (name == _store.get('$_photoNamePrefix$id') &&
        _store.get(photoKey) != null) {
      return false;
    }
    final res = await _http
        .get(_u('api/files/estimates/${r['id']}/$name'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return false;
    await _store.putRemote(photoKey, base64Encode(res.bodyBytes));
    await _store.putRemote('$_photoNamePrefix$id', name);
    return true;
  }

  /// Brings in records changed on the PC since the last time.
  Future<bool> _pull(SharedKind kind) async {
    final sinceKey = '$_sincePrefix${kind.collection}';
    final since = _store.get(sinceKey);
    var changed = false;
    var latest = since;
    for (var page = 1; ; page++) {
      final j = await _json(
        _http.get(
          _u(_records(kind.collection), {
            'sort': 'updated',
            'perPage': '200',
            'page': '$page',
            'filter': ?since == null ? null : 'updated>=${jsonEncode(since)}',
          }),
        ),
      );
      for (final r in (j['items'] as List).cast<Map>()) {
        final rec = r.cast<String, dynamic>();
        changed = await _apply(kind, rec) || changed;
        final u = rec['updated'] as String?;
        if (u != null && (latest == null || u.compareTo(latest) > 0)) {
          latest = u;
        }
      }
      if (page >= (j['totalPages'] as int? ?? 1)) break;
    }
    if (latest != null && latest != since) {
      await _store.putRemote(sinceKey, latest);
    }
    return changed;
  }

  /// One round: send what changed here, then fetch what changed on the PC.
  Future<void> sync(String baseUrl, http.Client client) async {
    _http = client;
    _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    if (_store.get(_versionKey) != version) {
      // First time (or more data shared): send everything once.
      for (final k in _store.keys.where(isSharedKey).toList()) {
        await _store.markChanged(k);
      }
    }
    // Estimates before their photos.
    final keys = _store.changedKeys
      ..sort(
        (a, b) => (a.startsWith(_photoPrefix) ? 1 : 0).compareTo(
          b.startsWith(_photoPrefix) ? 1 : 0,
        ),
      );
    rejected.clear();
    for (final k in keys) {
      try {
        await _sendKey(k);
      } on DataSyncException catch (e) {
        // The PC refused this item (e.g. an unreadable photo): keep it on
        // this phone and carry on with the rest instead of retrying it
        // every round.
        if (e.status < 400 || e.status >= 500) rethrow;
        rejected.add('$k: ${e.status}');
        await _store.markSent(k, _store.changeMark(k));
      }
    }
    var changed = false;
    for (final kind in sharedKinds) {
      changed = await _pull(kind) || changed;
    }
    await _store.putRemote(_versionKey, version);
    if (changed) onRemoteChange?.call();
  }

  /// The next bill number from the PC (so two phones never share one);
  /// null when the PC cannot be reached.
  Future<int?> nextNumber(
    String baseUrl,
    http.Client client,
    String counter,
    int atLeast,
  ) async {
    _http = client;
    _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    try {
      final j = await _json(
        _http.post(
          _u('api/damiyaas/counter'),
          headers: _headers,
          body: jsonEncode({'name': counter, 'min': atLeast}),
        ),
      );
      return (j['value'] as num).toInt();
    } catch (_) {
      return null;
    }
  }
}
