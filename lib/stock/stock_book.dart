import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../data/key_value_store.dart';
import 'stock_models.dart';

/// Thrown when a stock action is not allowed (shown to the user).
class StockException implements Exception {
  StockException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Daily stock counts, their approvals and audit trail, stored locally
/// (works offline) under their own keys — separate from price history.
///
/// Rules:
/// * A day's expected opening is the previous *verified* day's physical
///   count (its closing). Earlier days are never changed to absorb a
///   difference.
/// * Adjustments to expected stock, verification and reopening a verified
///   day need the manager PIN, and every action is logged.
class StockBook extends ChangeNotifier {
  StockBook(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final DateTime Function() _clock;

  static const _dayPrefix = 'stock_day_';
  static const _pinHashKey = 'stock_pin_hash';
  static const _pinSaltKey = 'stock_pin_salt';
  static const _employeeKey = 'stock_last_employee';

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static String dateKey(DateTime d) => _dateFmt.format(d);
  static DateTime parseDate(String key) => _dateFmt.parse(key);

  String get today => dateKey(_clock());

  // ---------------------------------------------------------------- storage

  /// All counted days, newest first.
  List<DailyStock> all() {
    final out = <DailyStock>[];
    for (final k in _store.keys.where((k) => k.startsWith(_dayPrefix))) {
      try {
        out.add(
          DailyStock.fromJson(
            jsonDecode(_store.get(k)!) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // Skip a corrupt day rather than failing the whole history.
      }
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  DailyStock? byDate(String date) {
    final raw = _store.get('$_dayPrefix$date');
    return raw == null
        ? null
        : DailyStock.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(DailyStock day) async {
    await _store.put('$_dayPrefix${day.date}', jsonEncode(day.toJson()));
    notifyListeners();
  }

  /// The most recent earlier count (any status) — shown as "Last day".
  DailyStock? dayBefore(String date) {
    for (final d in all()) {
      if (d.date.compareTo(date) < 0) return d;
    }
    return null;
  }

  /// The latest verified day before [date] — its count is [date]'s opening.
  DailyStock? verifiedBefore(String date) {
    for (final d in all()) {
      if (d.date.compareTo(date) < 0 && d.status == StockStatus.verified) {
        return d;
      }
    }
    return null;
  }

  /// The count for [date], creating it (with the carried-forward opening)
  /// if needed. A draft's opening follows the latest verified closing, so
  /// verifying yesterday later still updates today's expected stock.
  Future<DailyStock> open(String date) async {
    final existing = byDate(date);
    if (existing != null && existing.status != StockStatus.draft) {
      return existing;
    }
    final prev = verifiedBefore(date);
    final opening = prev?.counts ?? const <String, int>{};
    if (existing != null) {
      if (existing.openingFrom == prev?.date &&
          mapEquals(existing.opening, opening)) {
        return existing;
      }
      final refreshed = existing
          .copyWith(
            opening: opening,
            openingFrom: prev?.date,
            clearOpeningFrom: prev == null,
          )
          .logged(
            _event(
              'System',
              'Opening updated',
              prev == null
                  ? 'No verified closing stock'
                  : 'From verified closing of ${prev.date}',
            ),
          );
      await _save(refreshed);
      return refreshed;
    }
    final day = DailyStock(
      date: date,
      employee: lastEmployee,
      opening: opening,
      openingFrom: prev?.date,
      audit: [
        _event(
          lastEmployee.isEmpty ? 'Employee' : lastEmployee,
          'Count started',
          prev == null
              ? 'No verified closing stock yet — this count sets the opening'
              : 'Opening carried forward from verified closing of ${prev.date}',
        ),
      ],
    );
    await _save(day);
    return day;
  }

  // ------------------------------------------------------------ employee

  String get lastEmployee => _store.get(_employeeKey) ?? '';

  StockAuditEvent _event(String actor, String action, [String? detail]) =>
      StockAuditEvent(
        at: _clock(),
        actor: actor,
        action: action,
        detail: detail,
      );

  String _actor(DailyStock d) => d.employee.isEmpty ? 'Employee' : d.employee;

  void _requireDraft(DailyStock d) {
    if (d.status != StockStatus.draft) {
      throw StockException(
        d.status == StockStatus.verified
            ? 'This day is verified. A manager must reopen it to make changes.'
            : 'This count was submitted. Tap "Edit count" to change it.',
      );
    }
  }

  Future<DailyStock> setEmployee(DailyStock d, String name) async {
    _requireDraft(d);
    final n = name.trim();
    if (n == d.employee) return d;
    await _store.put(_employeeKey, n);
    final next = d
        .copyWith(employee: n)
        .logged(_event(n.isEmpty ? 'Employee' : n, 'Employee set', n));
    await _save(next);
    return next;
  }

  /// Sets the physical count of one item ([qty] null clears it), with the
  /// keypad working that produced it (e.g. "5+3-1").
  Future<DailyStock> setCount(
    DailyStock d,
    String code,
    int? qty, {
    String? expression,
  }) async {
    _requireDraft(d);
    if (qty != null && qty < 0) {
      throw StockException('Count cannot be negative');
    }
    final before = d.counts[code];
    final working = qty == null ? null : expression;
    if (before == qty && d.entries[code] == working) return d;
    final counts = {...d.counts};
    final entries = {...d.entries};
    qty == null ? counts.remove(code) : counts[code] = qty;
    working == null ? entries.remove(code) : entries[code] = working;
    final shown = working != null && CountExpression(working).hasWorking
        ? ' (${CountExpression(working).pretty})'
        : '';
    final next = d
        .copyWith(counts: counts, entries: entries)
        .logged(
          _event(
            _actor(d),
            'Count',
            '$code: ${before ?? '—'} → ${qty ?? '—'}$shown',
          ),
        );
    await _save(next);
    return next;
  }

  // ------------------------------------------------------------ auto-save

  static const _sessionKey = 'stock_session';

  /// Saves a draft as it stands on screen (typed names, a sum still being
  /// entered on the keypad) without adding audit entries — called every few
  /// seconds so nothing is lost if the app is closed. Returns the save time.
  Future<DateTime?> autosave(DailyStock d) async {
    if (d.status != StockStatus.draft) return null;
    final at = _clock();
    await _store.put(
      '$_dayPrefix${d.date}',
      jsonEncode(d.copyWith(savedAt: at).toJson()),
    );
    await _store.put(
      _sessionKey,
      jsonEncode({'date': d.date, 'savedAt': at.toIso8601String()}),
    );
    if (d.employee.trim().isNotEmpty) {
      await _store.put(_employeeKey, d.employee.trim());
    }
    notifyListeners();
    return at;
  }

  /// The last auto-saved count session: its date and save time.
  ({String date, DateTime savedAt})? get lastSession {
    final raw = _store.get(_sessionKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (
        date: j['date'] as String,
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<DailyStock> setRemark(DailyStock d, String code, String text) async {
    _requireDraft(d);
    final t = text.trim();
    if ((d.remarks[code] ?? '') == t) return d;
    final remarks = {...d.remarks};
    t.isEmpty ? remarks.remove(code) : remarks[code] = t;
    final next = d
        .copyWith(remarks: remarks)
        .logged(
          _event(
            _actor(d),
            'Remark',
            t.isEmpty ? '$code: removed' : '$code: $t',
          ),
        );
    await _save(next);
    return next;
  }

  Future<DailyStock> setNote(DailyStock d, String text) async {
    _requireDraft(d);
    final t = text.trim();
    if (d.note == t) return d;
    final next = d
        .copyWith(note: t)
        .logged(_event(_actor(d), 'Note', t.isEmpty ? 'removed' : t));
    await _save(next);
    return next;
  }

  /// Employee finishes counting; a manager then verifies.
  Future<DailyStock> submit(DailyStock d) async {
    _requireDraft(d);
    if (d.employee.trim().isEmpty) {
      throw StockException('Enter the employee name first');
    }
    final missing = stockItems.where((i) => !d.counts.containsKey(i.code));
    if (missing.isNotEmpty) {
      throw StockException(
        'Enter a count for every category (0 if none): '
        '${missing.map((i) => i.code).join(', ')}',
      );
    }
    final next = d
        .copyWith(status: StockStatus.submitted)
        .logged(
          _event(
            _actor(d),
            'Submitted',
            'Expected ${d.totalExpected}, physical ${d.totalCount}, '
                'difference ${_signed(d.totalDifference)}',
          ),
        );
    await _save(next);
    return next;
  }

  /// Takes a submitted (not yet verified) count back to draft.
  Future<DailyStock> editSubmitted(DailyStock d) async {
    if (d.status != StockStatus.submitted) return d;
    final next = d
        .copyWith(status: StockStatus.draft)
        .logged(
          _event(_actor(d), 'Back to draft', 'Count reopened for editing'),
        );
    await _save(next);
    return next;
  }

  // ------------------------------------------------------------- manager

  bool get hasManagerPin => _store.get(_pinHashKey) != null;

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  /// Sets the manager PIN. Changing an existing PIN needs the current one.
  Future<void> setManagerPin(String pin, {String? currentPin}) async {
    if (!validPin(pin)) throw StockException('PIN must be 4–8 digits');
    if (hasManagerPin && !checkPin(currentPin ?? '')) {
      throw StockException('Current PIN is incorrect');
    }
    final rnd = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => rnd.nextInt(256)));
    await _store.put(_pinSaltKey, salt);
    await _store.put(_pinHashKey, _hash(pin, salt));
    notifyListeners();
  }

  bool checkPin(String pin) {
    final hash = _store.get(_pinHashKey), salt = _store.get(_pinSaltKey);
    return hash != null && salt != null && _hash(pin, salt) == hash;
  }

  void _authorise(String manager, String pin) {
    if (manager.trim().isEmpty) throw StockException('Enter the manager name');
    if (!hasManagerPin) throw StockException('Set a manager PIN first');
    if (!checkPin(pin)) throw StockException('Incorrect manager PIN');
  }

  /// Adds a manager-approved adjustment to today's expected stock.
  Future<DailyStock> addAdjustment(
    DailyStock d, {
    required String code,
    required int qty,
    required String reason,
    required String manager,
    required String pin,
  }) async {
    _requireDraft(d);
    _authorise(manager, pin);
    if (qty == 0) throw StockException('Adjustment quantity cannot be 0');
    if (reason.trim().isEmpty) throw StockException('Enter a reason');
    final adj = StockAdjustment(
      code: code,
      qty: qty,
      reason: reason.trim(),
      approvedBy: manager.trim(),
      at: _clock(),
    );
    final next = d
        .copyWith(adjustments: [...d.adjustments, adj])
        .logged(
          _event(
            manager.trim(),
            'Adjustment approved',
            '$code ${_signed(qty)}: ${adj.reason}',
          ),
        );
    await _save(next);
    return next;
  }

  /// Manager verifies a submitted count; it becomes the next opening.
  Future<DailyStock> verify(
    DailyStock d, {
    required String manager,
    required String pin,
  }) async {
    if (d.status != StockStatus.submitted) {
      throw StockException('Only a submitted count can be verified');
    }
    _authorise(manager, pin);
    final next = d
        .copyWith(
          status: StockStatus.verified,
          approvedBy: manager.trim(),
          approvedAt: _clock(),
        )
        .logged(
          _event(
            manager.trim(),
            'Verified',
            'Closing stock ${d.totalCount}'
                '${d.totalDifference == 0 ? '' : ' (difference ${_signed(d.totalDifference)} recorded)'}',
          ),
        );
    await _save(next);
    return next;
  }

  /// Manager reopens a verified day (logged with a reason). Not allowed
  /// once a later day has been verified on top of it.
  Future<DailyStock> reopen(
    DailyStock d, {
    required String manager,
    required String pin,
    required String reason,
  }) async {
    if (d.status != StockStatus.verified) return d;
    _authorise(manager, pin);
    if (reason.trim().isEmpty) throw StockException('Enter a reason');
    final later = all().where(
      (x) => x.date.compareTo(d.date) > 0 && x.status == StockStatus.verified,
    );
    if (later.isNotEmpty) {
      throw StockException(
        'A later day (${later.last.date}) is already verified from this '
        'closing stock. Reopen that day first.',
      );
    }
    final next = d
        .copyWith(status: StockStatus.draft, clearApproval: true)
        .logged(_event(manager.trim(), 'Reopened', reason.trim()));
    await _save(next);
    return next;
  }

  /// Records that the summary was shared (WhatsApp, PDF…).
  Future<DailyStock> logShare(DailyStock d, String how) async {
    final next = d.logged(_event(_actor(d), 'Shared', how));
    await _save(next);
    return next;
  }

  static String _signed(int n) => n > 0 ? '+$n' : '$n';
}
