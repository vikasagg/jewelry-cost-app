import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../data/key_value_store.dart';
import '../ocr/ocr_service.dart';

/// One line of the shop's handwritten customer register.
class SalesEntry {
  const SalesEntry({
    required this.no,
    this.type = '',
    this.name = '',
    this.mobile = '',
    this.item = '',
    this.checked = true,
  });

  final int no;

  /// "R" (repeat customer), "N" (new) or empty.
  final String type;
  final String name;
  final String mobile;
  final String item;

  /// False for rows read from a photo that nobody has looked at yet.
  final bool checked;

  /// "4 / R", or just "4".
  String get numberLabel => type.isEmpty ? '$no' : '$no / $type';

  SalesEntry copyWith({
    int? no,
    String? type,
    String? name,
    String? mobile,
    String? item,
    bool? checked,
  }) => SalesEntry(
    no: no ?? this.no,
    type: type ?? this.type,
    name: name ?? this.name,
    mobile: mobile ?? this.mobile,
    item: item ?? this.item,
    checked: checked ?? this.checked,
  );

  Map<String, dynamic> toJson() => {
    'no': no,
    'type': type,
    'name': name,
    'mobile': mobile,
    'item': item,
    'checked': checked,
  };

  factory SalesEntry.fromJson(Map<String, dynamic> j) => SalesEntry(
    no: j['no'] as int? ?? 0,
    type: j['type'] as String? ?? '',
    name: j['name'] as String? ?? '',
    mobile: j['mobile'] as String? ?? '',
    item: j['item'] as String? ?? '',
    checked: j['checked'] as bool? ?? true,
  );
}

/// The register for one day.
class SalesRegister {
  const SalesRegister({required this.date, this.entries = const []});

  /// yyyy-MM-dd.
  final String date;
  final List<SalesEntry> entries;

  int get nextNumber => entries.fold(0, (m, e) => max(m, e.no)) + 1;

  int get unchecked => entries.where((e) => !e.checked).length;

  String get dateLabel =>
      DateFormat('d MMM yyyy').format(DateFormat('yyyy-MM-dd').parse(date));

  SalesRegister copyWith({List<SalesEntry>? entries}) =>
      SalesRegister(date: date, entries: entries ?? this.entries);

  Map<String, dynamic> toJson() => {
    'date': date,
    'entries': [for (final e in entries) e.toJson()],
  };

  factory SalesRegister.fromJson(Map<String, dynamic> j) => SalesRegister(
    date: j['date'] as String,
    entries: [
      for (final e in (j['entries'] as List? ?? const []))
        SalesEntry.fromJson((e as Map).cast<String, dynamic>()),
    ],
  );
}

/// Saved registers, one per day, on this phone.
class SalesRegisterBook extends ChangeNotifier {
  SalesRegisterBook(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  static const _prefix = 'sales_register_';

  String get today => DateFormat('yyyy-MM-dd').format(_clock());

  SalesRegister byDate(String date) {
    final raw = _store.get('$_prefix$date');
    if (raw == null) return SalesRegister(date: date);
    try {
      return SalesRegister.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SalesRegister(date: date);
    }
  }

  /// Every saved day, newest first.
  List<SalesRegister> all() {
    final out = [
      for (final k in _store.keys.where((k) => k.startsWith(_prefix)))
        byDate(k.substring(_prefix.length)),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> save(SalesRegister r) async {
    await _store.put('$_prefix${r.date}', jsonEncode(r.toJson()));
    notifyListeners();
  }

  /// Names and items written before, to correct what the camera misreads.
  ({List<String> names, List<String> items}) vocabulary() {
    final names = <String>{}, items = <String>{};
    for (final r in all()) {
      for (final e in r.entries.where((e) => e.checked)) {
        if (e.name.isNotEmpty) names.add(e.name);
        if (e.item.isNotEmpty) items.add(e.item);
      }
    }
    return (names: names.toList(), items: items.toList());
  }
}

/// Items the shop writes in the register (spelling used in reports).
const registerItems = [
  'Bali exchange',
  'Old gold exchange',
  'G-Ring sale',
  'G-Chain sale',
  'G-Coin sale',
  'G-Earring sale',
  'G-Bangle sale',
  'G-Pendant sale',
  'G-Nosepin sale',
  'G-Mangalsutra sale',
  'Diamond ring sale',
  'Silver payal sale',
  'Silver coin sale',
  'Silver earring sale',
  'Silver chain sale',
  'Coin sale',
  'Mala sale',
  'Repair',
  'Order booking',
];

String _letters(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = min(
        min(cur[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 1 = same letters, 0 = nothing alike (case, spaces, punctuation ignored).
double similarity(String a, String b) {
  final x = _letters(a), y = _letters(b);
  if (x.isEmpty || y.isEmpty) return 0;
  return 1 - _levenshtein(x, y) / max(x.length, y.length);
}

/// The closest of [known] to [text], if it is close enough.
String? closest(String text, Iterable<String> known, {double atLeast = 0.6}) {
  String? best;
  var score = atLeast;
  for (final k in known) {
    final s = similarity(text, k);
    if (s > score || (best == null && s == score)) {
      score = s;
      best = k;
    }
  }
  return best;
}

/// Tidies a name read from handwriting: "Mukeshji" → "Mukesh Ji".
String cleanName(String raw, {Iterable<String> known = const []}) {
  var t = raw.replaceAll(RegExp(r'[^A-Za-z .]'), ' ').trim();
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  var ji = false;
  // "ji" is often read as "ai" or "ii" from handwriting.
  final m = RegExp(r'^(.{3,}?)\s*([jJ][iI]|ai|ii)\.?$').firstMatch(t);
  if (m != null) {
    t = m.group(1)!.trim();
    ji = true;
  }
  if (t.isEmpty) return '';
  final words = [
    for (final w in t.split(' '))
      if (w.isNotEmpty) w[0].toUpperCase() + w.substring(1).toLowerCase(),
  ];
  final name = '${words.join(' ')}${ji ? ' Ji' : ''}';
  return closest(name, known, atLeast: 0.8) ?? name;
}

/// Tidies an item read from handwriting, matching the shop's usual items.
String cleanItem(String raw, {Iterable<String> known = const []}) {
  final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';
  return closest(t, {...known, ...registerItems}, atLeast: 0.55) ?? t;
}

/// Words on the page that are not register entries.
final _noise = RegExp(
  r'^(date|page|no\.?|name|item|mobile|s\.?\s?no\.?)$',
  caseSensitive: false,
);

/// Builds register lines from a photo of a register page: the left
/// column is the name (with the serial number and R/N before it), the
/// right column the item, and any 10-digit number the mobile. Numbers
/// start at [startNo]; rows are marked unchecked for the user to review.
List<SalesEntry> parseRegisterPage(
  OcrPage page, {
  int startNo = 1,
  Iterable<String> knownNames = const [],
  Iterable<String> knownItems = const [],
}) {
  final boxes = page.boxes
      .where((b) => b.text.trim().isNotEmpty && !_noise.hasMatch(b.text.trim()))
      .toList();
  if (boxes.isEmpty) return const [];

  final mobiles = <OcrBox>[], markers = <OcrBox>[], words = <OcrBox>[];
  for (final b in boxes) {
    final t = b.text.trim();
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      mobiles.add(b);
    } else if (RegExp(r'^([0-9]{1,3}|[RNrn]|[RN]\s*/\s*[RN])$').hasMatch(t)) {
      markers.add(b);
    } else if (_letters(t).length >= 2) {
      words.add(b);
    }
  }
  if (words.isEmpty) return const [];

  // Split names (left) from items (right) at the widest horizontal gap.
  final xs = words.map((b) => b.centerX).toList()..sort();
  var gap = 0.0, split = double.infinity;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] - xs[i - 1] > gap) {
      gap = xs[i] - xs[i - 1];
      split = (xs[i] + xs[i - 1]) / 2;
    }
  }
  if (gap < page.width * 0.15) split = double.infinity; // one column only
  final left = words.where((b) => b.centerX < split).toList()
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final right = words.where((b) => b.centerX >= split).toList()
    ..sort((a, b) => a.centerY.compareTo(b.centerY));

  // Line pitch from the column with more entries.
  final anchor = left.length >= right.length ? left : right;
  final other = identical(anchor, left) ? right : left;
  final gaps = [
    for (var i = 1; i < anchor.length; i++)
      anchor[i].centerY - anchor[i - 1].centerY,
  ]..sort();
  final heights = [for (final b in words) b.height]..sort();
  final pitch = gaps.isEmpty
      ? heights[heights.length ~/ 2] * 1.4
      : gaps[gaps.length ~/ 2];

  // Handwriting drifts, so the other column may sit a little lower or
  // higher: find the offset that lines most of it up with the anchor.
  var offset = 0.0, bestHits = -1, bestErr = double.infinity;
  for (var o = -pitch * 0.6; o <= pitch * 0.6; o += pitch / 20) {
    var hits = 0, err = 0.0;
    for (final b in other) {
      final d = anchor
          .map((a) => (b.centerY - o - a.centerY).abs())
          .reduce(min);
      if (d < pitch * 0.35) {
        hits++;
        err += d;
      }
    }
    if (hits > bestHits || (hits == bestHits && err < bestErr)) {
      bestHits = hits;
      bestErr = err;
      offset = o;
    }
  }

  // Rows: one per anchor box, plus any other-column box with no partner.
  final rows = [
    for (final a in anchor) <String, Object>{'y': a.centerY, 'anchor': a},
  ];
  for (final b in other) {
    final y = b.centerY - offset;
    Map<String, Object>? best;
    var d = pitch * 0.45;
    for (final r in rows) {
      final dd = ((r['y'] as double) - y).abs();
      if (dd < d && !r.containsKey('other')) {
        d = dd;
        best = r;
      }
    }
    if (best != null) {
      best['other'] = b;
    } else {
      rows.add({'y': y, 'other': b});
    }
  }
  rows.sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));

  Map<String, Object>? nearest(double y) {
    Map<String, Object>? best;
    var d = pitch * 0.5;
    for (final r in rows) {
      final dd = ((r['y'] as double) - y).abs();
      if (dd < d) {
        d = dd;
        best = r;
      }
    }
    return best;
  }

  for (final m in markers) {
    final r = nearest(m.centerY - (m.centerX >= split ? offset : 0));
    if (r == null) continue;
    final t = m.text.trim().toUpperCase().replaceAll(' ', '');
    if (RegExp(r'^[RN/]+$').hasMatch(t)) r['type'] = t.replaceAll('/', '-');
  }
  for (final m in mobiles) {
    final r = nearest(m.centerY);
    if (r != null) r['mobile'] = m.text.replaceAll(RegExp(r'\D'), '');
  }

  final out = <SalesEntry>[];
  for (final r in rows) {
    final nameBox =
        (identical(anchor, left) ? r['anchor'] : r['other']) as OcrBox?;
    final itemBox =
        (identical(anchor, left) ? r['other'] : r['anchor']) as OcrBox?;
    var type = r['type'] as String? ?? '';
    var nameText = nameBox?.text.trim() ?? '';
    // "NMosa ji": the R/N mark written right against the name.
    final lead = RegExp(r'^([RN])([A-Z][a-z].*)$').firstMatch(nameText);
    if (lead != null) {
      type = type.isEmpty ? lead.group(1)! : type;
      nameText = lead.group(2)!;
    }
    final name = cleanName(nameText, known: knownNames);
    final item = cleanItem(itemBox?.text ?? '', known: knownItems);
    if (name.isEmpty && item.isEmpty) continue;
    out.add(
      SalesEntry(
        no: startNo + out.length,
        type: type,
        name: name,
        mobile: r['mobile'] as String? ?? '',
        item: item,
        checked: false,
      ),
    );
  }
  return out;
}
