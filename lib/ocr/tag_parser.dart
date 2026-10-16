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
    this.diamondWeight = const ParsedField.missing(),
    this.stoneWeight = const ParsedField.missing(),
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
  final ParsedField<double> diamondWeight;
  final ParsedField<double> stoneWeight;
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
    add('diamondWeight', diamondWeight, 'diamond weight');
    add('stoneWeight', stoneWeight, 'stone weight');
    add('makingValue', makingValue, 'making charges');
    add('makingValue', makingMethod, 'making charge type');
    final wKey = wastageMethod.value == WastageMethod.weight
        ? 'wastageWeight'
        : 'wastagePercent';
    add(wKey, wastageValue, 'wastage');
    add(wKey, wastageMethod, 'wastage type');
    return out;
  }

  /// Required fields that could not be read at all.
  List<String> get missingRequired => [
    if (!goldWeight.isFound) 'goldWeight',
    if (!purity.isFound) 'purity',
  ];

  /// Builds a form input, layering tag values over [defaults].
  JewelleryInput toInput(JewelleryInput defaults) => JewelleryInput(
    itemName: itemName.value ?? defaults.itemName,
    tagNumber: tagNumber.value ?? defaults.tagNumber,
    purity: purity.value ?? defaults.purity,
    goldWeight: goldWeight.value ?? defaults.goldWeight,
    grossWeight: grossWeight.value ?? defaults.grossWeight,
    diamondWeight: diamondWeight.value ?? defaults.diamondWeight,
    diamondRate: defaults.diamondRate,
    excludeDiamond: defaults.excludeDiamond,
    stoneWeight: stoneWeight.value ?? defaults.stoneWeight,
    stoneRate: defaults.stoneRate,
    excludeStone: defaults.excludeStone,
    makingMethod: makingMethod.value ?? defaults.makingMethod,
    makingValue: makingValue.value ?? defaults.makingValue,
    wastageMethod: wastageMethod.value ?? defaults.wastageMethod,
    wastagePercent: wastageMethod.value == WastageMethod.percent
        ? wastageValue.value
        : defaults.wastagePercent,
    wastageWeight: wastageMethod.value == WastageMethod.weight
        ? wastageValue.value
        : defaults.wastageWeight,
    gst: defaults.gst,
  );
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
  static const _diamondLabel =
      r'(?:DIAMOND\s*W(?:EIGH)?T\.?|DIAMOND|DIA\.?\s*W(?:EIGH)?T\.?|DIA\.?|D\s?\.?\s?W\s?\.?\s?(?:T\b\.?)?)';
  static const _stoneLabel =
      r'(?:OTHER\s+STONES?\s*(?:W(?:EIGH)?T\.?)?|(?:COLOU?R(?:ED)?\s+)?STONES?\s*W(?:EIGH)?T\.?|STONES?|ST\.?\s*WT\.?|S\s?\.?\s?W\s?\.?\s?(?:T\b\.?)?|C\.?S\.?\s*WT\.?)';
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
        .replaceAll(RegExp('[¢©®°«»‘’“”]'), ' ');
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
    final diamondHits = _findWeights(visible(), _diamondLabel, consumed);
    final stoneHits = _findWeights(visible(), _stoneLabel, consumed);

    ParsedField<double> goldWeight;
    ParsedField<double> grossWeight;
    if (netHits.isNotEmpty && gwHits.isNotEmpty) {
      // "GW" + "NW" on the same tag: GW is almost certainly *gross* weight.
      final net = _toWeightField(netHits, 'gold weight', 'g', max: 1000);
      goldWeight = ParsedField(
        net.value,
        FieldConfidence.low,
        note: 'Tag shows both GW and NW. NW used as gold weight — confirm',
        source: net.source,
      );
      final g = _toWeightField(gwHits, 'gross weight', 'g', max: 2000);
      grossWeight = ParsedField(
        g.value,
        FieldConfidence.low,
        note: 'GW treated as gross jewellery weight — confirm',
        source: g.source,
      );
    } else {
      final goldSources = [...grossGoldHits, ...gwHits, ...netHits];
      goldWeight = _toWeightField(goldSources, 'gold weight', 'g', max: 1000);
      grossWeight = _toWeightField(grossHits, 'gross weight', 'g', max: 2000);
    }

    final diamondWeight = _toWeightField(
      diamondHits,
      'diamond weight',
      'ct',
      max: 50,
    );
    final stoneWeight = _toWeightField(
      stoneHits,
      'stone weight',
      'ct',
      max: 200,
    );

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
      diamondWeight: diamondWeight,
      stoneWeight: stoneWeight,
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

  // ----------------------------------------------------------------- purity

  ParsedField<Purity> _parsePurity(String text, List<List<int>> consumed) {
    final found = <Purity>[];
    final sources = <String>[];
    var reasons = <String>[];

    // Explicit karat: "18K", "18 KT", "22KARAT", "Purity: 18K", "22K916".
    final karatRe = RegExp(
      r'(?<![0-9A-Z.,])([0-9OoIl]{2})\s*(?:K|KT|KARAT|KARATS|CARAT\s+GOLD)(?![A-Z])',
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
        r'(?:PURITY|KARAT|KT|CARATAGE)\s*[:\-=]?\s*([0-9]{2,3})(?![0-9.])',
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

    // Hallmark fineness only (916, 750, 585, 999). Lowest priority.
    if (found.isEmpty) {
      final finRe = RegExp(r'(?<![0-9.,])(585|583|750|916|995|999)(?![0-9.,])');
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

    MakingMethod method = isPercent
        ? MakingMethod.percentOfGold
        : MakingMethod.fixed;
    var methodConfidence = FieldConfidence.high;
    String? methodNote;
    if (suffix.startsWith('/G') || suffix.startsWith('PERG')) {
      methodConfidence = FieldConfidence.low;
      methodNote =
          'Making charge is printed per gram (₹${n.cleaned}/g). '
          'Enter the total making amount or a % of gold value';
      reasons.add('per-gram making charge needs conversion');
    }
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
