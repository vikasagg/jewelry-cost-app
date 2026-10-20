import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/key_value_store.dart';
import 'stock_book.dart';
import 'stock_models.dart';

/// A member of staff from the shop PC's `staff` table.
class StaffMember {
  const StaffMember({required this.name, required this.phone});
  final String name;
  final String phone;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
  );
}

/// Talks to the PocketBase server on the shop PC (REST API).
class StockServer {
  StockServer(String baseUrl, {http.Client? client})
    : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _http = client ?? http.Client();

  final Uri base;
  final http.Client _http;
  static const _timeout = Duration(seconds: 8);
  static const _days = 'api/collections/stock_days/records';

  Uri _u(String path, [Map<String, String>? query]) =>
      base.resolve(path).replace(queryParameters: query);

  Future<Map<String, dynamic>> _json(Future<http.Response> req) async {
    final res = await req.timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StockServerException(res.statusCode, res.body);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static const _jsonHeaders = {
    'content-type': 'application/json; charset=utf-8',
  };

  /// Which staff have a PIN: name → true/false.
  Future<Map<String, bool>> pinStatus() async {
    final j = await _json(_http.get(_u('api/damiyaas/pin/status')));
    return {
      for (final r in (j['items'] as List).cast<Map>())
        r['name'] as String: r['has_pin'] == true,
    };
  }

  /// Creates or changes [name]'s PIN on the PC.
  Future<void> setPin(String name, String pin, String? current) => _json(
    _http.post(
      _u('api/damiyaas/pin/set'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'pin': pin, 'current': current ?? ''}),
    ),
  );

  /// Checks [name]'s PIN on the PC (StockServerException if wrong).
  Future<void> checkPin(String name, String pin) => _json(
    _http.post(
      _u('api/damiyaas/pin/check'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'pin': pin}),
    ),
  );

  /// True when the server answers.
  Future<void> ping() => _json(_http.get(_u('api/health')));

  Future<List<StaffMember>> staff() async {
    final j = await _json(
      _http.get(
        _u('api/collections/staff/records', {
          'filter': 'active=true',
          'sort': 'name',
          'perPage': '200',
        }),
      ),
    );
    return [
      for (final r in (j['items'] as List))
        StaffMember.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  /// Every stock day on the server (record id and the day).
  Future<List<(String, DailyStock)>> days() async {
    final out = <(String, DailyStock)>[];
    for (var page = 1; ; page++) {
      final j = await _json(
        _http.get(
          _u(_days, {
            'sort': '-date',
            'perPage': '200',
            'page': '$page',
            'fields': 'id,data',
          }),
        ),
      );
      for (final r in (j['items'] as List).cast<Map>()) {
        final data = r['data'];
        if (data is! Map) continue;
        try {
          out.add((
            r['id'] as String,
            DailyStock.fromJson(data.cast<String, dynamic>()),
          ));
        } catch (_) {
          // Skip a record the app cannot read.
        }
      }
      if (page >= (j['totalPages'] as int? ?? 1)) break;
    }
    return out;
  }

  Future<String?> _idFor(String date) async {
    final j = await _json(
      _http.get(
        _u(_days, {'filter': "date='$date'", 'fields': 'id', 'perPage': '1'}),
      ),
    );
    final items = j['items'] as List;
    return items.isEmpty ? null : (items.first as Map)['id'] as String;
  }

  /// The stock_days record for [d]: who counted, who approved, totals,
  /// one line per counted item (the server expands these into
  /// stock_count_items) and the full day for the app.
  static Map<String, dynamic> record(DailyStock d) => {
    'date': d.date,
    'status': d.status.name,
    'counted_by': d.employee,
    'approved_by': d.approvedBy ?? '',
    'approved_at': d.approvedAt?.toUtc().toIso8601String() ?? '',
    'total_expected': d.totalExpected,
    'total_count': d.totalCount,
    'total_difference': d.totalDifference,
    'lines': [
      for (final i in stockItems)
        if (d.counts.containsKey(i.code))
          {
            'code': i.code,
            'item': i.name,
            'group': i.group,
            'expected': d.expected(i.code),
            'counted': d.counts[i.code],
            'difference': d.difference(i.code),
            'remark': d.remarks[i.code] ?? '',
            'working': d.entries[i.code] ?? '',
          },
    ],
    'data': d.toJson(),
  };

  /// Creates or replaces the server copy of [d]; returns its record id.
  Future<String> put(DailyStock d, {String? knownId}) async {
    final body = jsonEncode(record(d));
    Future<String> patch(String id) async =>
        (await _json(
              _http.patch(_u('$_days/$id'), headers: _jsonHeaders, body: body),
            ))['id']
            as String;

    if (knownId != null) {
      try {
        return await patch(knownId);
      } on StockServerException catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final id = await _idFor(d.date);
    if (id != null) return patch(id);
    try {
      return (await _json(
            _http.post(_u(_days), headers: _jsonHeaders, body: body),
          ))['id']
          as String;
    } on StockServerException catch (e) {
      // Another phone created the day a moment ago.
      final again = e.status == 400 ? await _idFor(d.date) : null;
      if (again == null) rethrow;
      return patch(again);
    }
  }
}

class StockServerException implements Exception {
  StockServerException(this.status, this.body);
  final int status;
  final String body;

  /// The server's own message, e.g. "Incorrect PIN".
  String get message {
    try {
      final m = (jsonDecode(body) as Map)['message'];
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return 'Server error $status';
  }

  @override
  String toString() => message;
}

/// Personal PINs kept on the shop PC (when one is set), with a copy of
/// each PIN checked here so counting still works if the PC is off.
class SyncedStaffPins implements StaffPins {
  SyncedStaffPins(this._sync, this._local);
  final StockSync _sync;
  final LocalStaffPins _local;

  @override
  bool hasPin(String name) {
    if (!_sync.enabled) return _local.hasPin(name);
    final known = _sync._pinStatus[name.trim()];
    return known ?? _local.hasPin(name);
  }

  @override
  Future<void> setPin(String name, String pin, {String? currentPin}) async {
    if (!_sync.enabled) {
      return _local.setPin(name, pin, currentPin: currentPin);
    }
    if (!StockBook.validPin(pin)) {
      throw StockException('PIN must be 4–8 digits');
    }
    try {
      await _sync._server.setPin(name.trim(), pin, currentPin);
    } on StockServerException catch (e) {
      throw StockException(e.message);
    } catch (_) {
      throw StockException('Shop PC not reachable — connect to set a PIN');
    }
    await _local.remember(name, pin);
    await _sync._setPinStatus(name.trim(), true);
  }

  @override
  Future<void> verify(String name, String pin) async {
    if (!_sync.enabled) return _local.verify(name, pin);
    try {
      await _sync._server.checkPin(name.trim(), pin);
    } on StockServerException catch (e) {
      throw StockException(e.message);
    } catch (_) {
      // PC off: accept a PIN already checked on this phone.
      if (_local.hasPin(name)) return _local.verify(name, pin);
      throw StockException('Shop PC not reachable — cannot check the PIN');
    }
    await _local.remember(name, pin);
  }
}

enum SyncState { off, syncing, synced, offline }

/// Keeps this phone's stock counts and the shop PC's database in step:
/// changes made here are sent within a couple of seconds, and every
/// [interval] the phone fetches what other phones saved. Works offline:
/// unsent changes stay on the phone and go up when the PC is reachable.
class StockSync extends ChangeNotifier {
  StockSync(
    this._store,
    this._book, {
    http.Client? client,
    DateTime Function()? clock,
    this.interval = const Duration(seconds: 20),
    String? defaultUrl,
  }) : _client = client,
       _clock = clock ?? DateTime.now,
       _defaultUrl = defaultUrl {
    _book.onLocalChange = (_) => _schedulePush();
    _book.pins = SyncedStaffPins(this, LocalStaffPins(_store));
  }

  final KeyValueStore _store;
  final StockBook _book;
  final http.Client? _client;
  final DateTime Function() _clock;
  final Duration interval;
  final String? _defaultUrl;

  static const _urlKey = 'stock_server_url';
  static const _staffKey = 'stock_staff';
  static const _pinStatusKey = 'stock_pin_status';

  /// Which staff have created a PIN (from the PC; kept for offline use).
  Map<String, bool> get _pinStatus {
    final raw = _store.get(_pinStatusKey);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, bool>();
    } catch (_) {
      return const {};
    }
  }

  Future<void> _setPinStatus(String name, bool has) async {
    await _store.put(_pinStatusKey, jsonEncode({..._pinStatus, name: has}));
    notifyListeners();
  }

  static const _idPrefix = 'stock_rid_';
  static const _formatKey = 'stock_sync_format';

  /// Bumped when [StockServer.record] gains fields: every day is sent
  /// again once so the server has them.
  static const recordFormat = '2';

  SyncState state = SyncState.off;
  DateTime? lastSync;
  String? lastError;
  Timer? _push, _poll;
  bool _running = false, _again = false;

  /// e.g. "http://192.168.1.10:8090"; empty when not set.
  String get serverUrl => _store.get(_urlKey) ?? _defaultUrl ?? '';
  bool get enabled => serverUrl.isNotEmpty;

  StockServer get _server => StockServer(serverUrl, client: _client);

  /// Staff from the server (kept for offline use), sorted by name.
  List<StaffMember> get staff {
    final raw = _store.get(_staffKey);
    if (raw == null) return const [];
    try {
      return [
        for (final s in jsonDecode(raw) as List)
          StaffMember.fromJson((s as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  int get unsent => _book.unsentDates.length;

  /// Normalises what staff type ("192.168.1.10:8090" → http://…).
  static String normalise(String input) {
    var t = input.trim();
    if (t.isEmpty) return '';
    if (!t.contains('://')) t = 'http://$t';
    final u = Uri.tryParse(t);
    if (u == null || u.host.isEmpty) return '';
    return u
        .replace(path: '', query: null, fragment: null)
        .toString()
        .replaceAll(RegExp(r'[/?#]+$'), '');
  }

  /// Checks [url] answers as a PocketBase server with the stock tables.
  Future<String?> test(String url) async {
    final s = StockServer(url, client: _client);
    try {
      await s.ping();
      final staff = await s.staff();
      return staff.isEmpty ? 'Connected, but no staff found' : null;
    } on StockServerException catch (e) {
      return e.status == 404
          ? 'Connected, but the stock tables are missing. '
                'Copy pb_migrations next to PocketBase and restart it.'
          : 'Server error ${e.status}';
    } catch (e) {
      return 'Cannot reach $url';
    }
  }

  Future<void> setServerUrl(String url) async {
    _poll?.cancel();
    final u = normalise(url);
    await _store.put(_urlKey, u);
    // Record ids belong to the old server.
    for (final k
        in _store.keys.where((k) => k.startsWith(_idPrefix)).toList()) {
      await _store.delete(k);
    }
    // Everything on this phone goes up to the new server first.
    start(pushAll: true);
  }

  /// Starts periodic syncing (no-op without a server).
  void start({bool pushAll = false}) {
    _poll?.cancel();
    if (!enabled) {
      state = SyncState.off;
      notifyListeners();
      return;
    }
    _poll = Timer.periodic(interval, (_) => syncNow());
    syncNow(pushAll: pushAll);
  }

  void _schedulePush() {
    if (!enabled) return;
    _push?.cancel();
    _push = Timer(const Duration(seconds: 2), syncNow);
  }

  /// Sends unsent days, then fetches every day and the staff list.
  Future<void> syncNow({bool pushAll = false}) async {
    if (!enabled) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = SyncState.syncing;
    notifyListeners();
    try {
      final server = _server;
      String? rejected;
      final resend = pushAll || _store.get(_formatKey) != recordFormat;
      final dates = resend
          ? [for (final d in _book.all()) d.date]
          : _book.unsentDates;
      for (final date in dates) {
        final mark = _book.changeMark(date);
        final day = _book.byDate(date);
        if (day == null) {
          await _book.markSent(date, mark);
          continue;
        }
        try {
          final id = await server.put(
            day,
            knownId: _store.get('$_idPrefix$date'),
          );
          await _store.put('$_idPrefix$date', id);
          await _book.markSent(date, mark);
        } on StockServerException catch (e) {
          // The PC refused this day (e.g. counter approving their own
          // count): keep it here, carry on with the others.
          if (e.status != 400) rethrow;
          rejected = '$date: ${e.message}';
        }
      }
      for (final (id, day) in await server.days()) {
        await _store.put('$_idPrefix${day.date}', id);
        await _book.applyRemote(day);
      }
      await _store.put(
        _staffKey,
        jsonEncode([for (final s in await server.staff()) s.toJson()]),
      );
      try {
        await _store.put(_pinStatusKey, jsonEncode(await server.pinStatus()));
      } on StockServerException {
        // PC set up before personal PINs: PIN steps not installed yet.
      }
      await _store.put(_formatKey, recordFormat);
      state = SyncState.synced;
      lastSync = _clock();
      lastError = rejected;
    } catch (e) {
      state = SyncState.offline;
      lastError = e.toString();
    } finally {
      _running = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await syncNow();
    }
  }

  @override
  void dispose() {
    _push?.cancel();
    _poll?.cancel();
    super.dispose();
  }
}
