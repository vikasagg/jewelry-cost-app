import '../models/jewellery_input.dart';
import '../models/purity.dart';

/// How sure the parser is about a value.
enum FieldConfidence {
  /// Found with a clear label and a clean value.
  high,

  /// Found, but something was ambiguous — the user must confirm.
  low,

  /// Not found on the tag.
  missing,
}

/// A value extracted from tag text, with its provenance.
class ParsedField<T> {
  const ParsedField(this.value, this.confidence, {this.note, this.source});
  const ParsedField.missing()
    : value = null,
      confidence = FieldConfidence.missing,
      note = null,
      source = null;

  final T? value;
  final FieldConfidence confidence;

  /// Why the value needs confirmation (shown to the user).
  final String? note;

  /// The raw text fragment the value came from.
  final String? source;

  bool get needsConfirmation => confidence == FieldConfidence.low;
  bool get isFound => confidence != FieldConfidence.missing;
}

/// Structured result of parsing a jewellery tag.
class ParsedTag {
  const ParsedTag({
    required this.rawText,
    this.itemName = const ParsedField.missing(),
    this.tagNumber = const ParsedField.missing(),
    this.purity = const ParsedField.missing(),
    this.goldWeight = const ParsedField.missing(),
    this.grossWeight = const ParsedField.missing(),
    this.stones = const [],
    this.weightBalance,
    this.makingMethod = const ParsedField.missing(),
    this.makingValue = const ParsedField.missing(),
    this.wastageMethod = const ParsedField.missing(),
    this.wastageValue = const ParsedField.missing(),
  });

  final String rawText;
  final ParsedField<String> itemName;
  final ParsedField<String> tagNumber;
  final ParsedField<Purity> purity;
  final ParsedField<double> goldWeight;
  final ParsedField<double> grossWeight;

  /// Diamond / stone groups in the order printed on the tag.
  final List<ParsedStone> stones;

  /// Gross − net weight check, when both weights and stones were read.
  final WeightBalance? weightBalance;

  final ParsedField<MakingMethod> makingMethod;
  final ParsedField<double> makingValue;
  final ParsedField<WastageMethod> wastageMethod;

  /// Percentage or grams, depending on [wastageMethod].
  final ParsedField<double> wastageValue;

  /// Field keys (matching the details form) that need user confirmation.
  Map<String, String> get uncertainFields {
    final out = <String, String>{};
    void add(String key, ParsedField f, String label) {
      if (f.needsConfirmation) out[key] = f.note ?? 'Please confirm $label';
    }

    add('itemName', itemName, 'item name');
    add('tagNumber', tagNumber, 'tag number');
    add('purity', purity, 'gold purity');
    add('goldWeight', goldWeight, 'gold weight');
    add('grossWeight', grossWeight, 'gross weight');
    for (var i = 0; i < stones.length; i++) {
      add('stone.$i.weight', stones[i].weight, '${stones[i].label} weight');
      add('stone.$i.kind', stones[i].kind, '${stones[i].label} type');
    }
    add('makingValue', makingValue, 'making charges');
    add('makingValue', makingMethod, 'making charge type');
    // Wastage is not used by the app, so it never needs confirmation.
    return out;
  }

  /// Gross − gold weight (g) that no stone line accounts for, when the tag
  /// shows both weights but no stones were read — a sign stone lines were
  /// missed by OCR.
  double? get unreadStoneWeightG {
    final g = grossWeight.value, n = goldWeight.value;
    if (g == null || n == null || stones.isNotEmpty) return null;
    final d = g - n;
    return d > 0.01 ? d : null;
  }

  /// Required fields that could not be read at all.
  List<String> get missingRequired => [
    if (!goldWeight.isFound) 'goldWeight',
    if (!purity.isFound) 'purity',
  ];

  /// Builds a form input, layering tag values over [defaults].
  /// [rateFor] supplies the ₹/ct for a stone line from its printed rate code
  /// (or a remembered default when the line has no code).
  JewelleryInput toInput(
    JewelleryInput defaults, {
    double? Function(StoneKind kind, String? code)? rateFor,
  }) => JewelleryInput(
    itemName: itemName.value ?? defaults.itemName,
    tagNumber: tagNumber.value ?? defaults.tagNumber,
    purity: purity.value ?? defaults.purity,
    goldWeight: goldWeight.value ?? defaults.goldWeight,
    grossWeight: grossWeight.value ?? defaults.grossWeight,
    stones: stones.isEmpty
        ? defaults.stones
        : [
            for (final st in stones)
              StoneLine(
                kind: st.kind.value ?? StoneKind.diamond,
                label: st.label,
                weightCt: st.weight.value,
                code: st.code,
                ratePerCt: rateFor?.call(
                  st.kind.value ?? StoneKind.diamond,
                  st.code,
                ),
              ),
          ],
    excludeDiamond: defaults.excludeDiamond,
    excludeStone: defaults.excludeStone,
    makingMethod: makingMethod.value ?? defaults.makingMethod,
    makingValue: makingValue.value ?? defaults.makingValue,
    // Wastage is not used by the app (even if printed on the tag).
    wastageMethod: WastageMethod.none,
    gst: defaults.gst,
  );
}

/// How much useful data a parse found; used to pick the best of several
/// OCR attempts (e.g. different image rotations).
int scoreParsedTag(ParsedTag t) {
  var score = 0;
  if (t.goldWeight.isFound) score += 3;
  if (t.purity.isFound) score += 3;
  if (t.grossWeight.isFound) score += 1;
  if (t.tagNumber.isFound) score += 1;
  if (t.makingValue.isFound) score += 1;
  score += t.stones.length;
  if (t.weightBalance?.balances ?? false) score += 2;
  return score;
}

/// Total carats of diamond and polki lines. Stone lines are counted in
/// pieces, so they cannot take part in the gross − net weight balance.
double _caratTotal(List<ParsedStone> stones) => stones
    .where((st) => st.kind.value != StoneKind.stone)
    .fold(0.0, (a, st) => a + (st.weight.value ?? 0));

/// One diamond/stone group read from a tag.
class ParsedStone {
  const ParsedStone({
    required this.label,
    required this.weight,
    required this.kind,
    this.code,
  });

  /// Label as printed (normalised), e.g. "DIA", "FANCY CUT".
  final String label;
  final ParsedField<double> weight;
  final ParsedField<StoneKind> kind;

  /// Rate code printed after the weight (e.g. 700 in `DIA\\0.38\\700`).
  final String? code;
}

/// Gross weight − net (gold) weight compared with total stone carats
/// (1 ct = 0.2 g).
class WeightBalance {
  const WeightBalance({
    required this.grossG,
    required this.netG,
    required this.stonesCt,
  });

  final double grossG;
  final double netG;
  final double stonesCt;

  double get differenceG => grossG - netG;
  double get stonesG => stonesCt * 0.2;

  /// True when the stones account for the whole gross − net difference.
  bool get balances => (differenceG - stonesG).abs() <= _tolerance(grossG);

  static double _tolerance(double gross) =>
      gross * 0.001 > 0.006 ? gross * 0.001 : 0.006;

  String describe() =>
      'G.Wt ${grossG.toStringAsFixed(3)} − N.Wt ${netG.toStringAsFixed(3)} = '
      '${differenceG.toStringAsFixed(3)} g; stones '
      '${stonesCt.toStringAsFixed(2)} ct = ${stonesG.toStringAsFixed(3)} g';
}

class _Num {
  _Num(this.value, this.cleaned, this.reasons);
  final double value;
  final String cleaned;
  final List<String> reasons;
}

class _Hit {
  _Hit(this.start, this.end, this.number, this.unit, this.raw, this.labelText);
  final int start;
  final int end;
  final _Num number;
  final String? unit;
  final String raw;
  final String labelText;
}

/// Parses free-form OCR text from a printed jewellery tag.
///
/// The parser never silently guesses: anything ambiguous (character
/// substitutions, conflicting values, implausible magnitudes, comma decimals,
/// missing units, hallmark-only purity) is returned with
/// [FieldConfidence.low] and an explanatory note.
class TagParser {
  const TagParser();

  // A numeric token as OCR may produce it: digits with possible O/o/I/l/|
  // substitutions and a '.' or ',' decimal separator.
  static const _numToken =
      r'((?:[0-9OoIl|][0-9OoIl|]*(?:\s?[.,]\s?[0-9OoIl|]+)?)|(?:[.,][0-9]+))';
  // Separators between a label and its value. A '.' is only a separator when
  // it is not the start of a decimal like ".50".
  static const _sep = r'(?:[\s:=\-–#]|\.(?![0-9]))*';

  static const _grossGoldLabel = r'GROSS\s+GOLD\s+W(?:EIGH)?T\.?';
  static const _goldLabel =
      r'(?:GOLD\s*W(?:EIGH)?T\.?|GOLD\s+WEIGHT|G\s?\.?\s?W\s?\.?\s?(?:T\b\.?)?|G\.?\s?WT\.?|NET\s*W(?:EIGH)?T\.?|N\s?\.?\s?W\s?\.?\s?(?:T\b\.?)?)';
  static const _grossLabel =
      r'(?:GROSS\s*W(?:EIGH)?T\.?|GR\.?\s*WT\.?|GRS\.?\s*WT\.?|GROSS)';
  // Stone lines: LABEL [sep] weight [unit] [sep code], e.g. "DIA\0.38\700",
  // "D.W.: 0.50 ct", "FANCY CUT\2.13\850". OCR often turns the backslash
  // into "N", ")" or drops it entirely.
  static const _diamondLabel =
      r'DIAMONDS?(?:\s*W(?:EIGH)?T\.?)?|DIA\.?\s*W(?:EIGH)?T\.?|DIA|D\s?\.?\s?W\s?\.?\s?(?:T\b\.?)?|SOLITAIRE';
  // "Polki\0.50\300" — uncut diamonds, priced as their own section.
  static const _polkiLabel = r'POLKI(?:\s*W(?:EIGH)?T\.?)?';
  static const _fancyLabel = r'[A-Z@]{0,3}ANCY\s*CUT';
  // "Stn", "Stn.", "Stn.M" (stone) — priced like DIA lines: weight\code.
  static const _stoneLabel =
      r'STN\.?(?:\s*M\b\.?)?|OTHER\s+STONES?(?:\s*W(?:EIGH)?T\.?)?|(?:COLOU?R(?:ED)?\s+)?STONES?(?:\s*W(?:EIGH)?T\.?)?|ST\.?\s*WT\.?|S\s?\.?\s?W\s?\.?\s?(?:T\b\.?)?|C\.?S\.?\s*WT\.?|CZ|PEARLS?|RUBY|EMERALD|SAPPHIRE|KUNDAN|GEMS?(?:TONES?)?';
  static const _makingLabel =
      r'(?:MAKING\s*CHARGES?|MAKING|LABOU?R\s*CHARGES?|LABOU?R|M\s?\.?\s?C\s?\.?)';
  static const _wastageLabel =
      r'(?:WASTAGE|WSTG\.?|V\.?\s?A\.?|VALUE\s+ADD(?:ITION)?)';

  ParsedTag parse(String rawText) {
    // Work on a normalised copy whose indices match the original so we can
    // blank out consumed spans.
    var text = rawText
        .replaceAll('\r', '')
        .replaceAll(' ', ' ')
        .replaceAll('：', ':')
        // Stray glyphs OCR often inserts next to units (e.g. "10.50 ¢g").
        // Replaced with spaces so string indices stay aligned.
        .replaceAll(RegExp('[¢©®°«»‘’“”]'), ' ')
        // A 3-decimal weight run into the purity ("6.41014K" → "6.410 14K").
        .replaceAllMapped(
          RegExp(r'(\d\.\d{3})(9|14|18|20|22|24)(\s*K)', caseSensitive: false),
          (m) => '${m[1]} ${m[2]}${m[3]}',
        );
    final consumed = <List<int>>[];
    String visible() {
      final chars = text.split('');
      for (final c in consumed) {
        for (var i = c[0]; i < c[1] && i < chars.length; i++) {
          if (chars[i] != '\n') chars[i] = ' ';
        }
      }
      return chars.join();
    }

    final tagNumber = _parseTagNumber(text, consumed);
    final itemName = _parseItemName(text, consumed);

    // Weights. Order matters: the most specific labels go first and consume
    // their span so shorter labels (e.g. "GW") can't re-match them.
    final grossGoldHits = _findWeights(visible(), _grossGoldLabel, consumed);
    final grossHits = _findWeights(visible(), _grossLabel, consumed);
    final goldHitsAll = _findWeights(visible(), _goldLabel, consumed);
    final netHits = goldHitsAll
        .where((h) => h.labelText.trim().startsWith('N'))
        .toList();
    final gwHits = goldHitsAll
        .where((h) => !h.labelText.trim().startsWith('N'))
        .toList();
    final bothGwNw = netHits.isNotEmpty && gwHits.isNotEmpty;
    var goldWeight = _toWeightField(
      [...grossGoldHits, if (!bothGwNw) ...gwHits, ...netHits],
      'gold weight',
      'g',
      max: 1000,
    );
    var grossWeight = _toWeightField(
      [...grossHits, if (bothGwNw) ...gwHits],
      'gross weight',
      'g',
      max: 2000,
    );

    var stones = _parseStones(visible(), consumed);

    // Weight balance: gross − net should equal total stone carats × 0.2 g.
    WeightBalance? balance;
    final gross = grossWeight.value;
    final net = goldWeight.value;
    // Only possible when every line is in carats: stone lines are counted
    // in pieces, whose weight in grams is unknown.
    final allCarats =
        stones.isNotEmpty &&
        stones.every((st) => st.kind.value != StoneKind.stone);
    if (gross != null && net != null && allCarats) {
      stones = _resolveMerged(stones, gross, net);
      final ct = _caratTotal(stones);
      balance = WeightBalance(grossG: gross, netG: net, stonesCt: ct);
    }
    final balanced = balance?.balances ?? false;

    if (bothGwNw && !balanced) {
      // "GW" + "NW" on the same tag: GW is almost certainly *gross* weight,
      // but without a balancing stone total we ask the user to confirm.
      goldWeight = ParsedField(
        goldWeight.value,
        FieldConfidence.low,
        note: 'Tag shows both GW and NW. NW used as gold weight — confirm',
        source: goldWeight.source,
      );
      grossWeight = ParsedField(
        grossWeight.value,
        FieldConfidence.low,
        note: 'GW treated as gross jewellery weight — confirm',
        source: grossWeight.source,
      );
    }
    if (balance != null && !balanced) {
      final b = balance;
      stones = [
        for (final st in stones)
          ParsedStone(
            label: st.label,
            kind: st.kind,
            code: st.code,
            weight: ParsedField(
              st.weight.value,
              FieldConfidence.low,
              note:
                  'Diamond weights do not match gross − net weight '
                  '(${b.describe()}) — confirm',
              source: st.weight.source,
            ),
          ),
      ];
    }

    final making = _parseMaking(visible(), consumed);
    final wastage = _parseWastage(visible(), consumed);
    final purity = _parsePurity(visible(), consumed);

    return ParsedTag(
      rawText: rawText,
      itemName: itemName,
      tagNumber: tagNumber,
      purity: purity,
      goldWeight: goldWeight,
      grossWeight: grossWeight,
      stones: stones,
      weightBalance: balance,
      makingMethod: making.$1,
      makingValue: making.$2,
      wastageMethod: wastage.$1,
      wastageValue: wastage.$2,
    );
  }

  // ---------------------------------------------------------------- numbers

  _Num? _parseNumber(String token) {
    final reasons = <String>[];
    var t = token.replaceAll(RegExp(r'\s'), '');
    final substituted = t
        .replaceAll(RegExp('[Oo]'), '0')
        .replaceAll(RegExp('[Il|]'), '1');
    if (substituted != t) {
      reasons.add('characters in "$t" were read as digits');
      t = substituted;
    }
    if (t.contains(',')) {
      // On tags, a comma inside a weight is almost always a decimal mark
      // misread by OCR (or a European decimal). Flag it either way.
      t = t.replaceAll(',', '.');
      reasons.add('comma read as decimal point');
    }
    if ('.'.allMatches(t).length > 1) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return _Num(v, t, reasons);
  }

  List<_Hit> _findWeights(String text, String label, List<List<int>> consumed) {
    final re = RegExp(
      '(?<![A-Z0-9])(?<label>$label)$_sep$_numToken\\s*'
      r'(?<unit>GMS?|GRAMS?|GRMS?|G|CTS?|CARATS?|CRT|KT|K)?(?![A-Z])',
      caseSensitive: false,
    );
    final hits = <_Hit>[];
    for (final m in re.allMatches(text)) {
      final num = _parseNumber(m.group(2)!);
      if (num == null) continue;
      var unit = m.namedGroup('unit')?.toUpperCase();
      if (unit == 'K' || unit == 'KT') {
        // "G.W 18KT" — the number is a purity, not a weight. Skip.
        continue;
      }
      hits.add(
        _Hit(
          m.start,
          m.end,
          num,
          unit,
          m.group(0)!.trim(),
          m.namedGroup('label')!,
        ),
      );
      consumed.add([m.start, m.end]);
    }
    return hits;
  }

  ParsedField<double> _toWeightField(
    List<_Hit> hits,
    String label,
    String expectedUnit, {
    required double max,
  }) {
    if (hits.isEmpty) return const ParsedField.missing();
    final first = hits.first;
    final reasons = [...first.number.reasons];
    final distinct = hits.map((h) => h.number.value).toSet();
    if (distinct.length > 1) {
      reasons.add(
        'tag shows different values for $label '
        '(${distinct.map((v) => v.toString()).join(', ')})',
      );
    }
    final unit = first.unit;
    if (unit != null) {
      final isGrams = unit.startsWith('G');
      final isCarats = unit.startsWith('C');
      if ((expectedUnit == 'g' && isCarats) ||
          (expectedUnit == 'ct' && isGrams)) {
        reasons.add(
          'unit "$unit" is unusual for $label (expected $expectedUnit)',
        );
      }
    }
    final v = first.number.value;
    if (v > max) {
      reasons.add(
        '$v looks too large for $label — decimal point may be missing',
      );
    }
    if (v == 0 && expectedUnit == 'g') reasons.add('$label read as 0');
    return ParsedField(
      v,
      reasons.isEmpty ? FieldConfidence.high : FieldConfidence.low,
      note: reasons.isEmpty ? null : 'Confirm $label: ${reasons.join('; ')}',
      source: first.raw,
    );
  }

  // ----------------------------------------------------------------- stones

  List<ParsedStone> _parseStones(String text, List<List<int>> consumed) {
    final re = RegExp(
      '(?<![A-Z0-9])(?:(?<polki>$_polkiLabel)|(?<fancy>$_fancyLabel)|(?<dia>$_diamondLabel)|(?<stone>$_stoneLabel))'
      // separator: punctuation, or a backslash misread as N; may wrap a line
      r'[ \t]*(?:[:=\-–#\\/|()]|N(?=\s*[0-9.]))*[ \t]*\n?[ \t]*'
      r'(?<num>[0-9OoIl]*[.,][0-9OoIl]+|[0-9OoIl]+)'
      r'[ \t]*(?<unit>CTS?|CARATS?|CRT|GMS?|GRAMS?|G|KT|K)?(?![A-Z])'
      r'(?:[ \t]*(?:[\\/|():\-]|N)?[ \t]*(?<code>[0-9]{2,5})(?![0-9.,]))?',
      caseSensitive: false,
    );
    final out = <ParsedStone>[];
    for (final m in re.allMatches(text)) {
      final unit = m.namedGroup('unit')?.toUpperCase();
      if (unit == 'K' || unit == 'KT') continue; // a purity, not a weight
      final n = _parseNumber(m.namedGroup('num')!);
      if (n == null) continue;
      consumed.add([m.start, m.end]);

      final isFancy = m.namedGroup('fancy') != null;
      final isStone = m.namedGroup('stone') != null;
      final isPolki = m.namedGroup('polki') != null;
      final rawLabel = (m.namedGroup('dia') ?? m.namedGroup('stone') ?? '')
          .toUpperCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final label = isPolki
          ? 'POLKI'
          : isFancy
          ? 'FANCY CUT'
          : rawLabel.startsWith('STN')
          ? 'STN' // "Stn.M" is treated as "Stn"
          : rawLabel;

      final reasons = [...n.reasons];
      var value = n.value;
      var code = m.namedGroup('code');
      // "2.13850" / "2.131850": the separator before the code was lost.
      final decimals = n.cleaned.contains('.') ? n.cleaned.split('.')[1] : '';
      if (code == null && decimals.length > 3) {
        final intPart = n.cleaned.split('.')[0];
        value = double.parse('$intPart.${decimals.substring(0, 2)}');
        var rest = decimals.substring(2);
        if (rest.length > 3 && rest.startsWith('1')) rest = rest.substring(1);
        code = rest;
        reasons.add(
          'separator unclear in "${n.cleaned}" — read as '
          '${value.toStringAsFixed(2)} ct, code $code',
        );
      }
      if (unit != null && unit.startsWith('G')) {
        reasons.add('unit "$unit" is unusual for stones (expected ct)');
      }
      if (value > 100) reasons.add('$value ct looks too large');

      out.add(
        ParsedStone(
          label: label,
          code: code,
          weight: ParsedField(
            value,
            reasons.isEmpty ? FieldConfidence.high : FieldConfidence.low,
            note: reasons.isEmpty
                ? null
                : 'Confirm $label weight: ${reasons.join('; ')}',
            source: m.group(0)!.trim(),
          ),
          // FANCY CUT = fancy-shaped diamonds (confirmed with the retailer).
          kind: ParsedField(
            isPolki
                ? StoneKind.polki
                : isStone
                ? StoneKind.stone
                : StoneKind.diamond,
            FieldConfidence.high,
          ),
        ),
      );
    }
    return out;
  }

  /// For lines whose weight and code ran together, also try a 3-decimal
  /// split and keep whichever makes the weights balance. A split confirmed
  /// by the weight balance no longer needs confirmation.
  List<ParsedStone> _resolveMerged(
    List<ParsedStone> stones,
    double gross,
    double net,
  ) {
    bool balances(List<ParsedStone> s) => WeightBalance(
      grossG: gross,
      netG: net,
      stonesCt: _caratTotal(s),
    ).balances;

    final merged = [
      for (var i = 0; i < stones.length; i++)
        if ((stones[i].weight.note ?? '').contains('separator unclear')) i,
    ];
    if (merged.isEmpty) return stones;

    ParsedStone confirmed(ParsedStone st, double v, String? code) =>
        ParsedStone(
          label: st.label,
          kind: st.kind,
          code: code,
          weight: ParsedField(
            v,
            FieldConfidence.high,
            source: st.weight.source,
          ),
        );

    if (balances(stones)) {
      return [
        for (var i = 0; i < stones.length; i++)
          merged.contains(i)
              ? confirmed(stones[i], stones[i].weight.value!, stones[i].code)
              : stones[i],
      ];
    }
    for (final i in merged) {
      final digits = RegExp(
        r'([0-9]+)[.,]([0-9]{4,})',
      ).firstMatch(stones[i].weight.source ?? '');
      if (digits == null) continue;
      final dec = digits.group(2)!;
      final v3 = double.parse('${digits.group(1)}.${dec.substring(0, 3)}');
      var rest = dec.substring(3);
      if (rest.length > 3 && rest.startsWith('1')) rest = rest.substring(1);
      final trial = [...stones];
      trial[i] = confirmed(stones[i], v3, rest);
      if (balances(trial)) return trial;
    }
    return stones;
  }

  // ----------------------------------------------------------------- purity

  ParsedField<Purity> _parsePurity(String text, List<List<int>> consumed) {
    final found = <Purity>[];
    final sources = <String>[];
    var reasons = <String>[];

    // Explicit karat: "18K", "18 KT", "22KARAT", "Purity: 18K", "22K916", "9K".
    final karatRe = RegExp(
      r'(?<![0-9A-Z.,])([0-9OoIl]{2}|9)\s*(?:K|KT|KARAT|KARATS|CARAT\s+GOLD)(?![A-Z])',
      caseSensitive: false,
    );
    for (final m in karatRe.allMatches(text)) {
      final n = _parseNumber(m.group(1)!);
      if (n == null) continue;
      final p = Purity.fromKarat(n.value.round());
      if (p == null) continue;
      if (n.reasons.isNotEmpty) reasons.addAll(n.reasons);
      found.add(p);
      sources.add(m.group(0)!);
      consumed.add([m.start, m.end]);
    }

    // "Purity: 18" / "KT: 22" without a K suffix.
    if (found.isEmpty) {
      final labelRe = RegExp(
        r'(?:PURITY|KARAT|KT|CARATAGE)\s*[:\-=]?\s*([0-9]{1,3})(?![0-9.])',
        caseSensitive: false,
      );
      for (final m in labelRe.allMatches(text)) {
        final n = int.parse(m.group(1)!);
        final p = Purity.fromKarat(n) ?? Purity.fromFineness(n);
        if (p == null) continue;
        found.add(p);
        sources.add(m.group(0)!);
        if (Purity.fromKarat(n) == null) {
          reasons.add('purity inferred from fineness $n');
        }
        consumed.add([m.start, m.end]);
      }
    }

    // Hallmark fineness only (916, 833, 750, 585, 375, 999). Lowest priority.
    if (found.isEmpty) {
      final finRe = RegExp(
        r'(?<![0-9.,])(375|585|583|750|833|916|995|999)(?![0-9.,])',
      );
      for (final m in finRe.allMatches(text)) {
        final p = Purity.fromFineness(int.parse(m.group(1)!));
        if (p == null) continue;
        found.add(p);
        sources.add(m.group(0)!);
      }
      if (found.isNotEmpty) {
        reasons.add('purity inferred from hallmark fineness ${sources.first}');
      }
    }

    if (found.isEmpty) return const ParsedField.missing();
    if (found.toSet().length > 1) {
      reasons.add(
        'tag shows more than one purity '
        '(${found.toSet().map((p) => p.label).join(', ')})',
      );
    }
    reasons = reasons.toSet().toList();
    return ParsedField(
      found.first,
      reasons.isEmpty ? FieldConfidence.high : FieldConfidence.low,
      note: reasons.isEmpty ? null : 'Confirm purity: ${reasons.join('; ')}',
      source: sources.first,
    );
  }

  // ---------------------------------------------------- making & wastage

  (ParsedField<MakingMethod>, ParsedField<double>) _parseMaking(
    String text,
    List<List<int>> consumed,
  ) {
    final re = RegExp(
      '(?<![A-Z0-9])$_makingLabel$_sep'
      r'(?:RS\.?|INR|₹)?\s*'
      r'([0-9OoIl][0-9OoIl,]*(?:\.[0-9OoIl]+)?)\s*'
      r'(%|/\s*-|/\s*G(?:M|RAM)?S?\b|PER\s*G(?:M|RAM)?S?\b)?',
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    if (m == null) {
      return (const ParsedField.missing(), const ParsedField.missing());
    }
    consumed.add([m.start, m.end]);

    final reasons = <String>[];
    var token = m.group(1)!;
    final suffix = (m.group(2) ?? '').toUpperCase().replaceAll(' ', '');
    final isPercent = suffix == '%';
    if (!isPercent) {
      // Rupee amounts: commas are thousands separators (₹7,000).
      token = token.replaceAll(',', '');
    }
    final n = _parseNumber(token);
    if (n == null) {
      return (const ParsedField.missing(), const ParsedField.missing());
    }
    reasons.addAll(n.reasons);

    // Shop rule: making charges are per gram of gold weight unless the tag
    // says "%" or marks a total amount with "/-".
    final method = isPercent
        ? MakingMethod.percentOfGold
        : suffix.startsWith('/-')
        ? MakingMethod.fixed
        : MakingMethod.perGram;
    const methodConfidence = FieldConfidence.high;
    const String? methodNote = null;
    if (isPercent && n.value > 100) reasons.add('${n.value}% looks too high');

    return (
      ParsedField(
        method,
        methodConfidence,
        note: methodNote,
        source: m.group(0),
      ),
      ParsedField(
        n.value,
        reasons.isEmpty ? FieldConfidence.high : FieldConfidence.low,
        note: reasons.isEmpty
            ? null
            : 'Confirm making charges: ${reasons.join('; ')}',
        source: m.group(0)!.trim(),
      ),
    );
  }

  (ParsedField<WastageMethod>, ParsedField<double>) _parseWastage(
    String text,
    List<List<int>> consumed,
  ) {
    final re = RegExp(
      '(?<![A-Z0-9])$_wastageLabel$_sep$_numToken\\s*'
      r'(%|GMS?|GRAMS?|G)?(?![A-Z])',
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    if (m == null) {
      return (const ParsedField.missing(), const ParsedField.missing());
    }
    consumed.add([m.start, m.end]);
    final n = _parseNumber(m.group(1)!);
    if (n == null) {
      return (const ParsedField.missing(), const ParsedField.missing());
    }
    final unit = (m.group(2) ?? '').toUpperCase();
    final reasons = [...n.reasons];
    WastageMethod method;
    var methodConf = FieldConfidence.high;
    String? methodNote;
    if (unit == '%') {
      method = WastageMethod.percent;
    } else if (unit.startsWith('G')) {
      method = WastageMethod.weight;
    } else {
      method = WastageMethod.percent;
      methodConf = FieldConfidence.low;
      methodNote = 'Wastage has no unit on the tag — confirm % or grams';
      reasons.add('no unit printed');
    }
    return (
      ParsedField(method, methodConf, note: methodNote, source: m.group(0)),
      ParsedField(
        n.value,
        reasons.isEmpty ? FieldConfidence.high : FieldConfidence.low,
        note: reasons.isEmpty ? null : 'Confirm wastage: ${reasons.join('; ')}',
        source: m.group(0)!.trim(),
      ),
    );
  }

  // --------------------------------------------------------- identifiers

  ParsedField<String> _parseTagNumber(String text, List<List<int>> consumed) {
    final re = RegExp(
      r'(?<![A-Z])(?:TAG\s*(?:NO\.?|NUMBER|#|ID)?|ITEM\s*(?:CODE|NO\.?|#)|'
      r'PRODUCT\s*CODE|STYLE\s*(?:NO\.?|#)|SKU|BARCODE|CODE)\s*[:#\-.]?\s*'
      r'([A-Z0-9][A-Z0-9\-/]{2,})',
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    if (m == null) return const ParsedField.missing();
    consumed.add([m.start, m.end]);
    final value = m.group(1)!.toUpperCase();
    return ParsedField(value, FieldConfidence.high, source: m.group(0));
  }

  ParsedField<String> _parseItemName(String text, List<List<int>> consumed) {
    final re = RegExp(
      r'(?<![A-Z])(?:ITEM(?!\s*(?:CODE|NO|#))(?:\s*NAME)?|DESC(?:RIPTION)?|PRODUCT(?!\s*CODE)|ARTICLE)'
      r'\s*[:\-]\s*([^\n]+)',
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    if (m == null) return const ParsedField.missing();
    // Not consumed: names like "18K Diamond Ring" may carry the purity.
    // Stop the name at the next label on the same line, if any.
    final stop = RegExp(
      r'\s{2,}|\||\s(?=(?:G\.?\s?W|N\.?\s?W|D\.?\s?W|S\.?\s?W|GOLD\s*W|NET\s*W|GROSS|DIA\.?\s*W|'
      r'STONE\s*W|M\.?C\b|MAKING|WASTAGE|TAG\b|CODE\b|SKU\b|PURITY)[\s:.\-])',
      caseSensitive: false,
    );
    var value = m.group(1)!.split(stop).first.trim();
    if (value.isEmpty) return const ParsedField.missing();
    return ParsedField(value, FieldConfidence.high, source: m.group(0));
  }
}
