import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../branding.dart';
import '../core/money.dart';
import '../data/key_value_store.dart';
import '../models/purity.dart';

/// The day's gold and silver prices as the shop records them: gold 24K
/// per 10 g (other purities follow it), silver per kg.
class MetalPrice {
  const MetalPrice({
    required this.date,
    this.gold24Per10g,
    this.silverPerKg,
    required this.updatedAt,
  });

  /// yyyy-MM-dd.
  final String date;
  final double? gold24Per10g;
  final double? silverPerKg;
  final DateTime updatedAt;

  /// Gold per 10 g for [p] (22K = 92% of 24K, and so on).
  double? goldPer10g(Purity p) =>
      gold24Per10g == null ? null : gold24Per10g! * p.percentOf24 / 100;

  double? get silverPer10g => silverPerKg == null ? null : silverPerKg! / 100;

  String get dateLabel => DateFormat(
    'EEE, d MMM yyyy',
  ).format(DateFormat('yyyy-MM-dd').parse(date));

  Map<String, dynamic> toJson() => {
    'date': date,
    'gold24Per10g': gold24Per10g,
    'silverPerKg': silverPerKg,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MetalPrice.fromJson(Map<String, dynamic> j) => MetalPrice(
    date: j['date'] as String,
    gold24Per10g: (j['gold24Per10g'] as num?)?.toDouble(),
    silverPerKg: (j['silverPerKg'] as num?)?.toDouble(),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}

/// "₹1,23,450" (no paise when whole).
String rupees(double v) => formatInr(v).replaceAll(RegExp(r'\.00$'), '');

/// Today's rates as a message for WhatsApp.
String metalPriceText(MetalPrice p) {
  final s = StringBuffer()
    ..writeln('*${Brand.name}*')
    ..writeln('*Gold & Silver rates* — ${p.dateLabel}');
  if (p.gold24Per10g != null) {
    s.writeln();
    for (final k in [Purity.k24, Purity.k22, Purity.k18]) {
      s.writeln('Gold ${k.label}: ${rupees(p.goldPer10g(k)!)} / 10 g');
    }
  }
  if (p.silverPerKg != null) {
    s
      ..writeln()
      ..writeln('Silver: ${rupees(p.silverPerKg!)} / kg');
  }
  return s.toString().trimRight();
}

/// Recorded prices, one per day, on this phone.
class MetalPriceBook extends ChangeNotifier {
  MetalPriceBook(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  static const _prefix = 'metal_price_';

  String get today => DateFormat('yyyy-MM-dd').format(_clock());

  MetalPrice? byDate(String date) {
    final raw = _store.get('$_prefix$date');
    if (raw == null) return null;
    try {
      return MetalPrice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Every recorded day, newest first.
  List<MetalPrice> all() => [
    for (final k in _store.keys.where((k) => k.startsWith(_prefix)))
      ?byDate(k.substring(_prefix.length)),
  ]..sort((a, b) => b.date.compareTo(a.date));

  /// The latest record before [date] (to show the day's change).
  MetalPrice? before(String date) {
    for (final p in all()) {
      if (p.date.compareTo(date) < 0) return p;
    }
    return null;
  }

  /// The most recent price of each metal, from any day.
  ({double? gold24Per10g, double? silverPerKg}) get latest {
    double? g, s;
    for (final p in all()) {
      g ??= p.gold24Per10g;
      s ??= p.silverPerKg;
    }
    return (gold24Per10g: g, silverPerKg: s);
  }

  Future<MetalPrice> save(
    String date, {
    double? gold24Per10g,
    double? silverPerKg,
  }) async {
    final p = MetalPrice(
      date: date,
      gold24Per10g: gold24Per10g,
      silverPerKg: silverPerKg,
      updatedAt: _clock(),
    );
    await _store.put('$_prefix$date', jsonEncode(p.toJson()));
    notifyListeners();
    return p;
  }

  Future<void> delete(String date) async {
    await _store.delete('$_prefix$date');
    notifyListeners();
  }
}
