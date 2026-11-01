import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../data/key_value_store.dart';
import '../ocr/ocr_service.dart';

/// R = repeat customer, N = new, RN = repeat-new (as marked in the
/// register).
enum CustomerType {
  repeat('R', 'Repeat'),
  newCustomer('N', 'New'),
  repeatNew('RN', 'Repeat New');

  const CustomerType(this.code, this.label);
  final String code;
  final String label;

  /// "R", "N", "RN" (also "R/N", "R-N", "NR"); anything else is R.
  static CustomerType fromCode(String? code) {
    final c = (code ?? '').toUpperCase().replaceAll(RegExp(r'[^RN]'), '');
    if (c.contains('R') && c.contains('N')) return repeatNew;
    if (c == 'N') return newCustomer;
    return repeat;
  }
}

enum Deal {
  sale('Sale'),
  exchange('Exchange');

  const Deal(this.label);
  final String label;
}

enum Metal {
  gold('Gold'),
  silver('Silver'),
  diamond('Diamond'),
  others('Others');

  const Metal(this.label);
  final String label;
}

/// One line of the shop's handwritten customer register.
class SalesEntry {
  const SalesEntry({
    required this.no,
    this.type = CustomerType.repeat,
    this.name = '',
    this.mobile = '',
    this.deal = Deal.sale,
    this.metal = Metal.gold,
    this.item = '',
    this.checked = true,
    this.part = 0,
  });

  final int no;
  final CustomerType type;
  final String name;
  final String mobile;
  final Deal deal;
  final Metal metal;

  /// The article, e.g. "Chain", "Payal", "Coin".
  final String item;

  /// False for rows read from a photo that nobody has looked at yet.
  final bool checked;

  /// Which photo (1, 2, …) the line was read from; 0 = typed by hand.
  final int part;

  /// "4 / R".
  String get numberLabel => '$no / ${type.code}';

  /// "Gold · Chain · Sale".
  String get description =>
      [metal.label, if (item.isNotEmpty) item, deal.label].join(' · ');

  SalesEntry copyWith({
    int? no,
    CustomerType? type,
    String? name,
    String? mobile,
    Deal? deal,
    Metal? metal,
    String? item,
    bool? checked,
    int? part,
  }) => SalesEntry(
    no: no ?? this.no,
    type: type ?? this.type,
    name: name ?? this.name,
    mobile: mobile ?? this.mobile,
    deal: deal ?? this.deal,
    metal: metal ?? this.metal,
    item: item ?? this.item,
    checked: checked ?? this.checked,
    part: part ?? this.part,
  );

  Map<String, dynamic> toJson() => {
    'no': no,
    'type': type.code,
    'name': name,
    'mobile': mobile,
    'deal': deal.name,
    'metal': metal.name,
    'item': item,
    'checked': checked,
    'part': part,
  };

  factory SalesEntry.fromJson(Map<String, dynamic> j) {
    final raw = j['item'] as String? ?? '';
    // Lines saved before metal/deal were separate: read them from the item.
    final old = j['metal'] == null ? readItem(raw) : null;
    return SalesEntry(
      no: j['no'] as int? ?? 0,
      type: CustomerType.fromCode(j['type'] as String?),
      name: j['name'] as String? ?? '',
      mobile: j['mobile'] as String? ?? '',
      deal:
          old?.deal ??
          Deal.values.firstWhere(
            (d) => d.name == j['deal'],
            orElse: () => Deal.sale,
          ),
      metal:
          old?.metal ??
          Metal.values.firstWhere(
            (m) => m.name == j['metal'],
            orElse: () => Metal.others,
          ),
      item: old?.item ?? raw,
      checked: j['checked'] as bool? ?? true,
      part: j['part'] as int? ?? 0,
    );
  }
}

/// The register for one day.
class SalesRegister {
  const SalesRegister({required this.date, this.entries = const []});

  /// yyyy-MM-dd.
  final String date;
  final List<SalesEntry> entries;

  int get nextNumber => entries.fold(0, (m, e) => max(m, e.no)) + 1;

  int get unchecked => entries.where((e) => !e.checked).length;

  /// Photo parts merged into this register: part number → lines from it.
  Map<int, int> get parts {
    final out = <int, int>{};
    for (final e in entries.where((e) => e.part > 0)) {
      out[e.part] = (out[e.part] ?? 0) + 1;
    }
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  int get nextPart => parts.keys.fold(0, max) + 1;

  /// Numbers the lines 1, 2, 3… in their current order.
  SalesRegister renumbered() => copyWith(
    entries: [
      for (var i = 0; i < entries.length; i++) entries[i].copyWith(no: i + 1),
    ],
  );

  /// Adds the lines read from one more photo of the register. Lines that
  /// are already listed (the overlap between two photos of a page) are
  /// left out; the rest continue the numbering.
  ({SalesRegister register, int added, int skipped}) mergePart(
    List<SalesEntry> scanned,
  ) {
    final part = nextPart;
    final kept = <SalesEntry>[];
    var skipped = 0;
    for (final s in scanned) {
      if ([...entries, ...kept].any((e) => isSameLine(e, s))) {
        skipped++;
      } else {
        kept.add(s);
      }
    }
    var no = nextNumber;
    return (
      register: copyWith(
        entries: [
          ...entries,
          for (final k in kept) k.copyWith(no: no++, part: part),
        ],
      ),
      added: kept.length,
      skipped: skipped,
    );
  }

  /// Removes the lines read from photo [part] and renumbers.
  SalesRegister removePart(int part) => copyWith(
    entries: entries.where((e) => e.part != part).toList(),
  ).renumbered();

  /// Puts the lines of photo [part] first (it was the top of the page)
  /// and renumbers.
  SalesRegister movePartFirst(int part) => copyWith(
    entries: [
      ...entries.where((e) => e.part == part),
      ...entries.where((e) => e.part != part),
    ],
  ).renumbered();

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

/// True when two lines are the same register line read twice (for
/// example in the overlap of two photos of one page).
bool isSameLine(SalesEntry a, SalesEntry b) {
  final nameA = a.name.trim(), nameB = b.name.trim();
  final itemA = a.item.trim(), itemB = b.item.trim();
  if (a.mobile.isNotEmpty && a.mobile == b.mobile) return true;
  if (nameA.isEmpty && nameB.isEmpty) {
    return itemA.isNotEmpty && similarity(itemA, itemB) >= 0.9;
  }
  final names = similarity(nameA, nameB);
  if (itemA.isEmpty || itemB.isEmpty) return names >= 0.9;
  return names >= 0.7 && similarity(itemA, itemB) >= 0.7;
}

/// Articles written in the register (spelling used in reports).
const registerArticles = [
  'Ring',
  'Chain',
  'Coin',
  'Earring',
  'Bangle',
  'Pendant',
  'Nosepin',
  'Mangalsutra',
  'Payal',
  'Mala',
  'Bali',
  'Necklace',
  'Bracelet',
  'Kada',
  'Tops',
  'Locket',
  'Nath',
  'Tikka',
  'Set',
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

String _title(String t) => [
  for (final w in t.split(RegExp(r'\s+')))
    if (w.isNotEmpty) w[0].toUpperCase() + w.substring(1).toLowerCase(),
].join(' ');

/// Splits a register item such as "G-Chain sale", "Silver payal sale" or
/// "Bali exchange" into sale/exchange, metal (G- gold, D- diamond, S- or
/// "silver" silver, anything else others) and the article.
({Deal deal, Metal metal, String item}) readItem(
  String raw, {
  Iterable<String> known = const [],
}) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  var metal = Metal.others;
  // "G-…", "D-…", "S'…": the metal letter before a dash (C and 6 are
  // how a handwritten G is often read).
  final prefix = RegExp(r"^([GgCc6DdSs5])\s*[-'’.]\s*").firstMatch(t);
  if (prefix != null) {
    metal = switch (prefix.group(1)!.toUpperCase()) {
      'D' => Metal.diamond,
      'S' || '5' => Metal.silver,
      _ => Metal.gold,
    };
    t = t.substring(prefix.end);
  } else {
    final first = t.split(' ').first;
    final head = _letters(t.length > 6 ? t.substring(0, 6) : t);
    if (similarity(first, 'silver') >= 0.6 ||
        similarity(head, 'silver') >= 0.66) {
      metal = Metal.silver;
      t = similarity(first, 'silver') >= 0.6
          ? t.substring(first.length)
          : t.substring(6);
    } else if (similarity(first, 'gold') >= 0.75) {
      metal = Metal.gold;
      t = t.substring(first.length);
    } else if (similarity(first, 'diamond') >= 0.7 ||
        first.toLowerCase() == 'dia') {
      metal = Metal.diamond;
      t = t.substring(first.length);
    }
  }
  t = t.replaceAll(RegExp(r'^[^A-Za-z]+'), '').trim();

  // Sale or exchange: the last word (or the end of a run-together word).
  var deal = Deal.sale;
  final words = t.split(' ').where((w) => w.isNotEmpty).toList();
  bool like(String w, String target, double at) => similarity(w, target) >= at;
  if (_letters(t).contains('exch') ||
      (words.isNotEmpty && like(words.last, 'exchange', 0.6))) {
    deal = Deal.exchange;
  }
  // "sale" is often misread ("sor", "sle"): a short last word with an s.
  bool saleLike(String w) =>
      like(w, 'sale', 0.5) ||
      (_letters(w).length <= 4 && _letters(w).startsWith('s'));
  if (words.length > 1 &&
      (saleLike(words.last) || like(words.last, 'exchange', 0.6))) {
    words.removeLast();
  } else if (words.length == 1) {
    final w = words.single;
    final l = _letters(w);
    final ex = l.indexOf('exch');
    if (ex > 1) {
      words[0] = w.substring(0, w.toLowerCase().indexOf('exch'));
    } else if (l.length > 6 && like(l.substring(l.length - 4), 'sale', 0.5)) {
      words[0] = w.substring(0, w.length - 4);
    }
  }
  final rest = words.join(' ').replaceAll(RegExp(r'[^A-Za-z ]'), '').trim();
  if (rest.isEmpty) return (deal: deal, metal: metal, item: '');

  // Match the shop's articles: the whole text, else its best word.
  final vocab = {...known, ...registerArticles};
  final whole = closest(rest, vocab, atLeast: 0.6);
  if (whole != null) return (deal: deal, metal: metal, item: whole);
  String? best;
  var score = 0.6;
  for (final w in rest.split(' ')) {
    for (final v in vocab) {
      final sc = similarity(w, v);
      if (sc > score) {
        score = sc;
        best = v;
      }
    }
  }
  return (deal: deal, metal: metal, item: best ?? _title(rest));
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
    } else if (RegExp(
      r'^([0-9]{1,3}|[RNrn]|[RNrn]\s*[/-]?\s*[RNrn])$',
    ).hasMatch(t)) {
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
    if (RegExp(r'^[RN/-]+$').hasMatch(t)) r['type'] = t;
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
    var type = r['type'] as String?;
    var nameText = nameBox?.text.trim() ?? '';
    // "NMosa ji": the R/N mark written right against the name.
    final lead = RegExp(r'^([RN])([A-Z][a-z].*)$').firstMatch(nameText);
    if (lead != null) {
      type ??= lead.group(1)!;
      nameText = lead.group(2)!;
    }
    final name = cleanName(nameText, known: knownNames);
    final read = readItem(itemBox?.text ?? '', known: knownItems);
    if (name.isEmpty && (itemBox?.text.trim() ?? '').isEmpty) continue;
    out.add(
      SalesEntry(
        no: startNo + out.length,
        type: CustomerType.fromCode(type),
        name: name,
        mobile: r['mobile'] as String? ?? '',
        deal: read.deal,
        metal: read.metal,
        item: read.item,
        checked: false,
      ),
    );
  }
  return out;
}
