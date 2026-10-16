import '../core/money.dart';
import '../models/gold_rates.dart';
import '../models/jewellery_input.dart';
import '../pricing/pricing_engine.dart';
import 'widgets/common.dart';

/// Plain-text cost summary for sharing/exporting.
String buildSummaryText(JewelleryInput i, PricingResult r, GoldRates rates) {
  final b = StringBuffer()
    ..writeln('JEWELLERY COST SUMMARY')
    ..writeln('Estimate only — not a tax invoice')
    ..writeln('');
  if (i.tagNumber != null) b.writeln('Tag no: ${i.tagNumber}');
  b
    ..writeln('Purity: ${r.purity.label}')
    ..writeln('Gold weight: ${i.goldWeight!.toStringAsFixed(3)} g');
  if (i.grossWeight != null) {
    b.writeln('Gross weight: ${i.grossWeight!.toStringAsFixed(3)} g');
  }
  for (var k = 0; k < i.stones.length; k++) {
    final s = i.stones[k];
    if (!s.hasWeight) continue;
    final value = k < r.stoneLinePaise.length ? r.stoneLinePaise[k] : 0;
    b.writeln(
      '${s.displayName} (${s.kind.label.toLowerCase()}): '
      '${s.weightCt!.toStringAsFixed(2)} ct'
      '${s.ratePerCt == null ? '' : ' × ${formatInr(s.ratePerCt!)}/ct = ${formatPaise(value)}'}',
    );
  }
  b
    ..writeln('')
    ..writeln(
      'Gold rate (${r.purity.label}): ${formatInr(r.goldRatePerGram)}/g '
      '(rates of ${formatDateTime(rates.updatedAt)})',
    )
    ..writeln('Gold value: ${formatPaise(r.goldValuePaise)}')
    ..write(
      r.diamondValuePaise > 0
          ? 'Diamond value: ${formatPaise(r.diamondValuePaise)}\n'
          : '',
    )
    ..write(
      r.stoneValuePaise > 0
          ? 'Stone value: ${formatPaise(r.stoneValuePaise)}\n'
          : '',
    )
    ..write(
      r.polkiValuePaise > 0
          ? 'Polki value: ${formatPaise(r.polkiValuePaise)}\n'
          : '',
    )
    ..writeln('Making charges: ${formatPaise(r.makingPaise)}')
    ..writeln('Subtotal: ${formatPaise(r.subtotalPaise)}')
    ..writeln('Taxable subtotal: ${formatPaise(r.taxableBasePaise)}');
  for (final l in r.gstLines) {
    b.writeln(
      '${l.label} @ ${formatPercent(l.ratePercent)}% on '
      '${formatPaise(l.basePaise)}: ${formatPaise(l.amountPaise)}',
    );
  }
  b
    ..writeln('')
    ..writeln('TOTAL ESTIMATED COST: ${formatPaise(r.totalPaise)}');
  return b.toString();
}
