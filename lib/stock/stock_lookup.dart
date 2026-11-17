import '../data/repositories.dart';
import '../models/jewellery_input.dart';
import '../models/purity.dart';

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _s(Object? v) => (v ?? '').toString().trim();

/// Purity from the export's Gold Std ("22K", "18 KT", "916", "750"…).
Purity? purityFromStd(String std) {
  final s = std.toUpperCase();
  final k = RegExp(r'(\d{1,2})\s*K').firstMatch(s);
  if (k != null) return Purity.fromKarat(int.parse(k.group(1)!));
  final f = RegExp(r'\b(\d{3})\b').firstMatch(s);
  return f == null ? null : Purity.fromFineness(int.parse(f.group(1)!));
}

/// Fills the manual entry form from a stock_items record (from the stock
/// export): weights, purity, diamonds, stones / polki and making. Rates in
/// the export are read like tag rate codes ([rateFor]: code × the tag
/// rate multiplier). What the record does not have is kept from
/// [current] (GST, wastage, and purity when there is no Gold Std).
JewelleryInput inputFromStockItem(
  Map<String, dynamic> item,
  JewelleryInput current, {
  required double? Function(StoneKind kind, String? code) rateFor,
}) {
  String? code(Object? rate) => _n(rate) > 0 ? _s(rate) : null;
  double? rateOf(StoneKind kind, String? c) => c == null
      ? PricingDefaultsRepository.manualLineRate[kind]
      : rateFor(kind, c);

  final stones = <StoneLine>[];
  final diaWt = _n(item['dia_detail_wt']) > 0
      ? _n(item['dia_detail_wt'])
      : _n(item['dia_wt']);
  if (diaWt > 0) {
    final c = code(item['dia_rate']);
    stones.add(
      StoneLine(
        kind: StoneKind.diamond,
        label: _s(item['dia_item']).isEmpty ? null : _s(item['dia_item']),
        weightCt: diaWt,
        ratePerCt: rateOf(StoneKind.diamond, c),
        code: c,
      ),
    );
  }
  final stnItem = _s(item['stn_item']);
  final stnWt = _n(item['stn_detail_wt']) > 0
      ? _n(item['stn_detail_wt'])
      : _n(item['stone_wt']);
  final stnPcs = _n(item['stn_pcs']);
  final c = code(item['stn_rate']);
  if (stnItem.toUpperCase().contains('POLKI')) {
    if (stnWt > 0) {
      stones.add(
        StoneLine(
          kind: StoneKind.polki,
          label: stnItem,
          weightCt: stnWt,
          ratePerCt: rateOf(StoneKind.polki, c),
          code: c,
        ),
      );
    }
  } else if (stnPcs > 0 || stnItem.isNotEmpty || stnWt > 0) {
    // Stones are priced per piece. Without a piece count the export's
    // stone value (weight × rate) becomes one piece at that value.
    final value = _n(item['stn_value']);
    final asOne = stnPcs <= 0 && value > 0;
    stones.add(
      StoneLine(
        kind: StoneKind.stone,
        label: stnItem.isEmpty ? null : stnItem,
        weightCt: stnPcs > 0
            ? stnPcs
            : asOne
            ? 1
            : null,
        ratePerCt: asOne
            ? value
            : c == null
            ? null
            : rateFor(StoneKind.stone, c),
        code: asOne ? null : c,
      ),
    );
  }

  final perGram = _n(item['labour_per_gm']), fixed = _n(item['labour_rs']);
  final gold = _n(item['gold_wt']) > 0
      ? _n(item['gold_wt'])
      : _n(item['net_wt']);
  final gross = _n(item['gross_wt']);
  return JewelleryInput(
    itemName: _s(item['item_name']).isEmpty
        ? current.itemName
        : _s(item['item_name']),
    tagNumber: _s(item['tag_no']),
    purity: purityFromStd(_s(item['gold_std'])) ?? current.purity,
    goldWeight: gold > 0 ? gold : current.goldWeight,
    grossWeight: gross > 0 ? gross : current.grossWeight,
    stones: stones,
    makingMethod: perGram > 0
        ? MakingMethod.perGram
        : fixed > 0
        ? MakingMethod.fixed
        : current.makingMethod,
    makingValue: perGram > 0
        ? perGram
        : fixed > 0
        ? fixed
        : current.makingValue,
    wastageMethod: current.wastageMethod,
    wastagePercent: current.wastagePercent,
    wastageWeight: current.wastageWeight,
    gst: current.gst,
  );
}
