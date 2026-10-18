import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../branding.dart';
import '../../core/money.dart';
import '../../models/gold_rates.dart';
import '../../models/jewellery_input.dart';
import '../../models/purity.dart';
import '../../pricing/pricing_engine.dart';
import '../summary_text.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/price_icons.dart';
import 'bill_screen.dart';
import 'details_form_screen.dart';
import 'scan_screen.dart';

/// Itemised cost summary with actions. Pops with the saved record id.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.input,
    required this.ratesSnapshot,
    this.recordId,
    this.source = 'manual',
    this.openedFromForm = false,
    this.savedAt,
    this.image,
  });

  /// Thumbnail of the scanned tag; for saved records it is loaded from
  /// history when not given.
  final Uint8List? image;

  final JewelleryInput input;
  final GoldRates ratesSnapshot;
  final String? recordId;
  final String source;
  final bool openedFromForm;
  final DateTime? savedAt;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late JewelleryInput _input = widget.input;

  /// Purity as read from the tag / entered on the form.
  late final Purity? _originalPurity = widget.input.purity;
  late GoldRates _rates = widget.ratesSnapshot;
  late String? _recordId = widget.recordId;
  late final Uint8List? _image =
      widget.image ??
      (widget.recordId == null
          ? null
          : AppScope.read(context).imageFor(widget.recordId!));
  PricingResult? _result;
  List<PricingIssue> _issues = const [];
  bool _dirty = true; // not yet saved in its current form

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_result == null && _issues.isEmpty) {
      _compute();
      // Every new or edited estimate is saved to history automatically;
      // records opened from history are only re-saved on request.
      if (_result != null && widget.savedAt == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _save(auto: true);
        });
      }
    }
    if (widget.savedAt != null) _dirty = false;
  }

  void _compute() {
    final o = AppScope.read(context).engine.calculate(_input, _rates.perGram);
    _result = o.result;
    _issues = o.issues;
  }

  Future<void> _save({bool auto = false}) async {
    final state = AppScope.read(context);
    final rec = await state.saveCalculation(
      input: _input,
      ratesSnapshot: _rates,
      result: _result!,
      existingId: _recordId,
      source: widget.source,
      image: widget.image,
    );
    if (!mounted) return;
    setState(() {
      _recordId = rec.id;
      _dirty = false;
    });
    final tag = _input.tagNumber;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          auto
              ? 'Saved to history${tag == null ? '' : ' as $tag'}'
              : 'Saved to history',
        ),
      ),
    );
  }

  /// Re-prices the estimate for another purity (picked on this screen) and
  /// keeps the saved history record in step with what is shown.
  Future<void> _changePurity(Purity p) async {
    if (p == _input.purity) return;
    setState(() {
      _input = _input.copyWith(purity: p);
      _compute();
      _dirty = true;
    });
    if (_result != null && _recordId != null) await _save(auto: true);
  }

  /// Scanned tag photo, shown small (decoded at thumbnail size); tap to
  /// enlarge.
  Widget _photoHeader(JewelleryInput i, PricingResult r) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        GestureDetector(
          key: const Key('resultPhoto'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                child: Image.memory(_image, fit: BoxFit.contain),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _image!,
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              cacheWidth: 252, // decode small: 84 px at up to 3× density
              gaplessPlayback: true,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i.tagNumber ?? 'Scanned tag',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${r.purity.label} gold · ${i.goldWeight!.toStringAsFixed(3)} g',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                formatDateTime(widget.savedAt ?? AppScope.of(context).now()),
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _purityPicker() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const Text(
          'Gold purity',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<Purity>(
            key: const Key('resultPurity'),
            initialValue: _input.purity,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              for (final p in Purity.values.reversed)
                if (_rates.rateFor(p) != null)
                  DropdownMenuItem(
                    value: p,
                    child: Text(
                      overflow: TextOverflow.ellipsis,
                      '${p.label}${p == _originalPurity ? (widget.source == 'scan' ? ' (from tag)' : ' (entered)') : ''}'
                      ' · ${formatInr(_rates.quotedRateFor(p)!)}/${_rates.quoteUnit}',
                    ),
                  ),
            ],
            onChanged: (p) {
              if (p != null) _changePurity(p);
            },
          ),
        ),
      ],
    ),
  );

  /// Saves this estimate if needed, then builds a bill with it ticked
  /// (more saved products can be added).
  Future<void> _generateBill() async {
    if (_recordId == null || _dirty) await _save(auto: true);
    if (!mounted || _recordId == null) return;
    await startBill(context, preselectId: _recordId);
  }

  void _recalculate() {
    final current = AppScope.read(context).rates;
    if (current == null) return;
    final before = _result?.totalPaise;
    final changed = current != _rates;
    setState(() {
      _rates = current;
      _compute();
      if (changed) _dirty = true;
    });
    final msg = !changed
        ? 'Recalculated — rates unchanged'
        : before == _result?.totalPaise
        ? 'Recalculated with current gold rates — total unchanged'
        : 'Recalculated with current gold rates (${formatDateTime(current.updatedAt)})';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _edit() async {
    if (widget.openedFromForm) {
      Navigator.of(context).pop(_recordId);
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DetailsFormScreen(
          initial: _input,
          ratesSnapshot: _rates,
          recordId: _recordId,
        ),
      ),
    );
  }

  void _scanAnother() {
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => const ScanScreen()));
  }

  final _summaryKey = GlobalKey();
  final _scroll = ScrollController();
  bool _sharingImage = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Captures the cost summary card as a PNG and opens the share sheet
  /// (pick WhatsApp there).
  Future<void> _sendImage() async {
    setState(() => _sharingImage = true);
    try {
      // The card must be on screen to be painted.
      if (_scroll.hasClients && _scroll.offset > 0) {
        await _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _summaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Summary not visible');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not create image');
      final tag = (_input.tagNumber ?? 'estimate').replaceAll(
        RegExp(r'[^A-Za-z0-9-]'),
        '_',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'jewellery-estimate-$tag.png',
            ),
          ],
          text:
              '${Brand.name} – jewellery cost estimate${_input.tagNumber == null ? '' : ' – ${_input.tagNumber}'}: '
              '${formatPaise(_result!.totalPaise)}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share the image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  Future<void> _share() async {
    final text = buildSummaryText(_input, _result!, _rates);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share cost summary'),
              subtitle: const Text('WhatsApp, email, messages…'),
              onTap: () async {
                Navigator.pop(sheet);
                try {
                  await SharePlus.instance.share(
                    ShareParams(
                      text: text,
                      subject: 'Jewellery cost – ${_input.displayName}',
                    ),
                  );
                } catch (_) {
                  await _copy(text);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Copy to clipboard'),
              onTap: () {
                Navigator.pop(sheet);
                _copy(text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cost summary copied')));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<String>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_recordId);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cost Summary'),
          actions: const [HistoryAction(), RatesAction()],
        ),
        body: SafeArea(
          child: ResponsiveBody(
            child: _result == null ? _issuesView() : _resultView(_result!),
          ),
        ),
      ),
    );
  }

  /// One line per stone group, e.g. "DIA 0.38 ct × ₹70,000.00 = ₹26,600.00".
  String? _stonesCaption(JewelleryInput i, PricingResult r, StoneKind kind) {
    final excluded = i.isExcluded(kind);
    final lines = <String>[];
    for (var k = 0; k < i.stones.length; k++) {
      final s = i.stones[k];
      if (s.kind != kind || !s.hasWeight) continue;
      final w = s.isPieces
          ? '${s.displayName} ${formatPercent(s.weightCt!)} pcs'
          : '${s.displayName} ${s.weightCt!.toStringAsFixed(2)} ct';
      if (excluded || s.ratePerCt == null) {
        lines.add(w);
      } else {
        final v = k < r.stoneLinePaise.length ? r.stoneLinePaise[k] : null;
        lines.add(
          '$w × ${formatInr(s.ratePerCt!)}'
          '${s.effectiveFactor == 1 ? '' : ' × ${s.effectiveFactor}'}'
          '${v == null ? '' : ' = ${formatPaise(v)}'}',
        );
      }
    }
    if (lines.isEmpty) return null;
    return [if (excluded) 'Excluded', ...lines].join('\n');
  }

  Widget _issuesView() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Cannot calculate yet',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      for (final i in _issues)
        ListTile(
          leading: const Icon(Icons.error_outline, color: AppColors.error),
          title: Text(i.message),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _edit,
        icon: const Icon(Icons.edit),
        label: const Text('Edit Details'),
      ),
    ],
  );

  Widget _resultView(PricingResult r) {
    final i = _input;
    final current = AppScope.of(context).rates;
    final historical = current != null && current != _rates;
    return ListView(
      key: const Key('resultList'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Photo and purity picker sit outside the summary card, so the
        // WhatsApp image never shows the tag (with its rate codes).
        if (_image != null) _photoHeader(i, r),
        _purityPicker(),
        RepaintBoundary(
          key: _summaryKey,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Branded header — this card is what customers receive
                  // as the WhatsApp image.
                  BrandHeader(
                    subtitle:
                        'Jewellery Cost Estimate · ${formatDateTime(widget.savedAt ?? AppScope.of(context).now())}',
                  ),
                  const SizedBox(height: 12),

                  // Jewellery details
                  const SectionTitle('Jewellery Details'),
                  if ((i.tagNumber ?? '').trim().isNotEmpty)
                    InfoRow(
                      icon: PriceIcons.tag,
                      label: 'Tag No.',
                      value: i.tagNumber!,
                    ),
                  InfoRow(
                    icon: PriceIcons.purity,
                    label: 'Gold Purity',
                    value: r.purity.label,
                  ),
                  InfoRow(
                    icon: PriceIcons.weight,
                    label: 'Gold Weight',
                    value: '${i.goldWeight!.toStringAsFixed(3)} g',
                  ),
                  if (i.diamondWeight > 0)
                    InfoRow(
                      icon: PriceIcons.diamond,
                      label: 'Diamond Weight',
                      value: '${i.diamondWeight.toStringAsFixed(2)} ct',
                    ),
                  if (i.stoneWeight > 0)
                    InfoRow(
                      icon: PriceIcons.stone,
                      label: 'Stones',
                      value: '${formatPercent(i.stoneWeight)} pcs',
                    ),
                  if (i.polkiWeight > 0)
                    InfoRow(
                      icon: PriceIcons.polki,
                      label: 'Polki Weight',
                      value: '${i.polkiWeight.toStringAsFixed(2)} ct',
                    ),
                  if (i.grossWeight != null)
                    InfoRow(
                      icon: PriceIcons.grossWeight,
                      label: 'Gross Weight',
                      value: '${i.grossWeight!.toStringAsFixed(3)} g',
                    ),
                  const Divider(),

                  // Price breakdown
                  const SectionTitle('Price Breakdown'),
                  BreakdownRow(
                    icon: PriceIcons.rate,
                    label: 'Applicable gold rate (${r.purity.label})',
                    value: '${formatInr(r.goldRatePerGram)}/g',
                    caption: 'Rates saved ${formatDateTime(_rates.updatedAt)}',
                  ),
                  BreakdownRow(
                    icon: PriceIcons.gold,
                    label: 'Gold value',
                    valueKey: const Key('goldValue'),
                    value: formatPaise(r.goldValuePaise),
                    caption:
                        '${i.goldWeight!.toStringAsFixed(3)} g × ${formatInr(r.goldRatePerGram)}',
                  ),
                  // Zero-value lines are left out of the estimate.
                  if (r.diamondValuePaise > 0)
                    BreakdownRow(
                      icon: PriceIcons.diamond,
                      label: 'Diamond value',
                      value: formatPaise(r.diamondValuePaise),
                      caption: _stonesCaption(i, r, StoneKind.diamond),
                    ),
                  if (r.stoneValuePaise > 0)
                    BreakdownRow(
                      icon: PriceIcons.stone,
                      label: 'Stone value',
                      value: formatPaise(r.stoneValuePaise),
                      caption: _stonesCaption(i, r, StoneKind.stone),
                    ),
                  if (r.polkiValuePaise > 0)
                    BreakdownRow(
                      icon: PriceIcons.polki,
                      label: 'Polki value',
                      value: formatPaise(r.polkiValuePaise),
                      caption: _stonesCaption(i, r, StoneKind.polki),
                    ),
                  // Wastage is no longer used; shown only for old saved records.
                  if (r.wastagePaise > 0)
                    BreakdownRow(
                      icon: PriceIcons.wastage,
                      label: 'Wastage charges',
                      value: formatPaise(r.wastagePaise),
                    ),
                  BreakdownRow(
                    icon: PriceIcons.labour,
                    label: 'Making charges',
                    value: formatPaise(r.makingPaise),
                    caption: switch (i.makingMethod) {
                      MakingMethod.perGram =>
                        '${formatInr(i.makingValue!)}/g × ${i.goldWeight!.toStringAsFixed(3)} g',
                      MakingMethod.fixed => 'Fixed amount',
                      MakingMethod.percentOfGold =>
                        '${formatPercent(i.makingValue!)}% of gold value',
                    },
                  ),
                  const Divider(height: 16),
                  BreakdownRow(
                    icon: PriceIcons.subtotal,
                    label: 'Subtotal',
                    value: formatPaise(r.subtotalPaise),
                    bold: true,
                  ),
                  BreakdownRow(
                    icon: PriceIcons.subtotal,
                    label: 'Taxable subtotal',
                    value: formatPaise(r.taxableBasePaise),
                    caption: r.gstLines.isEmpty
                        ? 'No components taxable'
                        : r.gstLines
                              .expand((l) => l.components)
                              // Only parts that actually add to the base.
                              .where((c) => r.componentPaise(c) > 0)
                              .map(
                                (c) => c.label
                                    .replaceAll(' value', '')
                                    .replaceAll(' charges', ''),
                              )
                              .join(' + '),
                  ),
                  for (final l in r.gstLines)
                    BreakdownRow(
                      icon: PriceIcons.gst,
                      label: '${l.label} @ ${formatPercent(l.ratePercent)}%',
                      value: formatPaise(l.amountPaise),
                      caption: 'on ${formatPaise(l.basePaise)}',
                    ),
                  if (r.gstLines.isEmpty)
                    BreakdownRow(
                      icon: PriceIcons.gst,
                      label: 'GST',
                      value: '₹0.00',
                    ),
                  const SizedBox(height: 10),
                  // Total, highlighted as in the design.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.goldSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.monetization_on_outlined,
                          size: 40,
                          color: AppColors.gold,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Estimated Cost',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  formatPaise(r.totalPaise),
                                  key: const Key('total'),
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.goldDeep,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Estimate only — not a tax invoice.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (historical || widget.savedAt != null) ...[
          const SizedBox(height: 12),
          _RatesUsedCard(rates: _rates, highlight: r.purity, current: current),
        ],
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final bill = _recordId == null
                ? null
                : AppScope.of(context).billFor(_recordId!);
            return FilledButton.icon(
              key: const Key('generateBill'),
              onPressed: () =>
                  bill == null ? _generateBill() : showBill(context, bill),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(
                bill == null ? 'Generate Bill' : 'View Bill ${bill.billNo}',
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('sendWhatsApp'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF25D366), // WhatsApp green
          ),
          onPressed: _sharingImage ? null : _sendImage,
          icon: const Icon(Icons.send),
          label: Text(_sharingImage ? 'Preparing image…' : 'Send on WhatsApp'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('saveHistory'),
          onPressed: _dirty ? _save : null,
          icon: Icon(
            _dirty ? Icons.bookmark_add_outlined : Icons.bookmark_added,
          ),
          label: Text(
            _dirty
                ? (_recordId == null ? 'Save to History' : 'Update in History')
                : 'Saved to History',
          ),
        ),
        const SizedBox(height: 10),
        TileGrid(
          minTileWidth: 160,
          children: [
            OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Details'),
            ),
            OutlinedButton.icon(
              key: const Key('recalculate'),
              onPressed: _recalculate,
              icon: const Icon(Icons.refresh),
              label: const Text('Recalculate'),
            ),
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('Share as text'),
            ),
            OutlinedButton.icon(
              onPressed: _scanAnother,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan Another'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Recalculate applies the current saved gold rates.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _RatesUsedCard extends StatelessWidget {
  const _RatesUsedCard({
    required this.rates,
    required this.highlight,
    this.current,
  });
  final GoldRates rates;
  final Purity highlight;
  final GoldRates? current;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Gold rates used for this calculation',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(
            'Saved ${formatDateTime(rates.updatedAt)}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          TileGrid(
            minTileWidth: 140,
            children: [
              for (final p in Purity.values)
                if (rates.rateFor(p) != null)
                  StatTile(
                    label:
                        p.label +
                        (current != null &&
                                current!.rateFor(p) != rates.rateFor(p)
                            ? ' (now ${formatInr(current!.rateFor(p) ?? 0)})'
                            : ''),
                    value: formatInr(rates.rateFor(p) ?? 0),
                    highlight: p == highlight,
                  ),
            ],
          ),
        ],
      ),
    ),
  );
}
