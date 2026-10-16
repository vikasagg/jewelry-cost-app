import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../models/gold_rates.dart';
import '../../models/jewellery_input.dart';
import '../../models/purity.dart';
import '../../ocr/tag_parser.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// Editable jewellery details — used after a scan, for manual entry and for
/// editing a saved calculation.
class DetailsFormScreen extends StatefulWidget {
  const DetailsFormScreen({
    super.key,
    this.parsed,
    this.initial,
    this.ratesSnapshot,
    this.recordId,
  });

  /// OCR result to pre-fill from (scan flow).
  final ParsedTag? parsed;

  /// Existing input to edit (history flow).
  final JewelleryInput? initial;

  /// Rates to price with; defaults to the current saved rates.
  final GoldRates? ratesSnapshot;

  /// When editing a saved record.
  final String? recordId;

  @override
  State<DetailsFormScreen> createState() => _DetailsFormScreenState();
}

class _DetailsFormScreenState extends State<DetailsFormScreen> {
  final _c = <String, TextEditingController>{
    for (final k in [
      'itemName',
      'tagNumber',
      'goldWeight',
      'grossWeight',
      'makingValue',
      'wastagePercent',
      'wastageWeight',
      'gstRate',
      'gstMakingRate',
    ])
      k: TextEditingController(),
  };

  Purity? _purity;
  MakingMethod _making = MakingMethod.perGram;
  WastageMethod _wastage = WastageMethod.none;
  final _stones = <_StoneRow>[];
  bool _excludeDiamond = false;
  bool _excludeStone = false;
  Set<PriceComponent> _taxable = PriceComponent.values.toSet();
  bool _separateMakingGst = false;

  GoldRates? _snapshot;
  String? _recordId;
  final _uncertain = <String, String>{};
  final _missing = <String>{};
  final _errors = <String, String>{};
  bool _initialised = false;

  bool get _isScan => widget.parsed != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final state = AppScope.read(context);
    _snapshot = widget.ratesSnapshot ?? state.rates;
    _recordId = widget.recordId;

    final defaults = state.pricingDefaults;
    final input =
        widget.initial ??
        widget.parsed?.toInput(defaults, rateFor: state.stoneRateFor) ??
        defaults;
    _load(input);
    final parsed = widget.parsed;
    if (parsed != null) {
      _uncertain.addAll(parsed.uncertainFields);
      _missing.addAll(parsed.missingRequired);
    }
  }

  void _load(JewelleryInput i) {
    _c['itemName']!.text = i.itemName ?? '';
    _c['tagNumber']!.text = i.tagNumber ?? '';
    _c['goldWeight']!.text = formatInput(i.goldWeight);
    _c['grossWeight']!.text = formatInput(i.grossWeight);
    for (final r in _stones) {
      r.dispose();
    }
    _stones
      ..clear()
      ..addAll(
        i.stones.map(
          (l) => _StoneRow.from(
            l,
            codeRate: l.code == null
                ? null
                : AppScope.read(context).stoneRateFor(l.kind, l.code),
          ),
        ),
      );
    _c['makingValue']!.text = formatInput(i.makingValue);
    _c['wastagePercent']!.text = formatInput(i.wastagePercent);
    _c['wastageWeight']!.text = formatInput(i.wastageWeight);
    _c['gstRate']!.text = formatInput(i.gst.ratePercent);
    _c['gstMakingRate']!.text = formatInput(i.gst.makingRatePercent);
    _purity = i.purity;
    _making = i.makingMethod;
    _wastage = i.wastageMethod;
    _excludeDiamond = i.excludeDiamond;
    _excludeStone = i.excludeStone;
    _taxable = i.gst.taxable.toSet();
    _separateMakingGst = i.gst.makingRatePercent != null;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final r in _stones) {
      r.dispose();
    }
    super.dispose();
  }

  double? _num(String key) {
    final v = parseNumber(_c[key]!.text);
    return v;
  }

  String? _text(String key) {
    final t = _c[key]!.text.trim();
    return t.isEmpty ? null : t;
  }

  JewelleryInput _buildInput() => JewelleryInput(
    itemName: _text('itemName'),
    tagNumber: _text('tagNumber'),
    purity: _purity,
    goldWeight: _num('goldWeight'),
    grossWeight: _num('grossWeight'),
    stones: [for (final r in _stones) r.toLine()],
    excludeDiamond: _excludeDiamond,
    excludeStone: _excludeStone,
    makingMethod: _making,
    makingValue: _num('makingValue'),
    wastageMethod: _wastage,
    wastagePercent: _num('wastagePercent'),
    wastageWeight: _num('wastageWeight'),
    gst: GstConfig(
      ratePercent: _num('gstRate'),
      taxable: _taxable,
      makingRatePercent: _separateMakingGst ? _num('gstMakingRate') : null,
    ),
  );

  void _edited(String key) {
    setState(() {
      _errors.remove(key);
      _uncertain.remove(key);
      _missing.remove(key);
    });
  }

  void _confirm(String key) => setState(() => _uncertain.remove(key));

  FieldState _stateOf(String key) => _missing.contains(key)
      ? FieldState.missing
      : _uncertain.containsKey(key)
      ? FieldState.uncertain
      : FieldState.normal;

  static const _textKeys = {'itemName', 'tagNumber'};

  static const _labels = {
    'itemName': 'Item name',
    'tagNumber': 'Tag number',
    'purity': 'Gold purity',
    'goldWeight': 'Gold weight',
    'grossWeight': 'Gross weight',
    'makingValue': 'Making charges',
    'wastagePercent': 'Wastage %',
    'wastageWeight': 'Wastage weight',
  };

  String _labelOf(String key) {
    final m = RegExp(r'^stone\.(\d+)\.(weight|rate|kind)$').firstMatch(key);
    if (m != null) {
      final i = int.parse(m.group(1)!);
      final name = i < _stones.length ? _stones[i].displayName : 'Stone';
      return '$name ${m.group(2) == 'kind' ? 'type' : m.group(2)}';
    }
    return _labels[key] ?? key;
  }

  void _addStone(StoneKind kind) {
    final state = AppScope.read(context);
    setState(() {
      _stones.add(
        _StoneRow.from(
          StoneLine(kind: kind, ratePerCt: state.stoneRateFor(kind, null)),
        ),
      );
    });
  }

  /// Removes a stone line and shifts the index-based field keys after it.
  void _removeStone(int index) {
    Map<String, V> shift<V>(Map<String, V> m) {
      final out = <String, V>{};
      m.forEach((k, v) {
        final mm = RegExp(r'^stone\.(\d+)\.(.+)$').firstMatch(k);
        if (mm == null) {
          out[k] = v;
          return;
        }
        final i = int.parse(mm.group(1)!);
        if (i == index) return;
        out['stone.${i > index ? i - 1 : i}.${mm.group(2)}'] = v;
      });
      return out;
    }

    setState(() {
      _stones.removeAt(index).dispose();
      final u = shift(_uncertain);
      _uncertain
        ..clear()
        ..addAll(u);
      final e = shift(_errors);
      _errors
        ..clear()
        ..addAll(e);
    });
  }

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    if (_uncertain.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Please confirm scanned values'),
          content: Text(
            'These values were unclear on the tag. Check each one against the '
            'tag, correct it if needed, then tap Confirm:\n\n'
            '${_uncertain.keys.map((k) => '• ${_labelOf(k)}').join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Review'),
            ),
          ],
        ),
      );
      return;
    }
    final input = _buildInput();
    final errors = <String, String>{};
    _c.forEach((k, c) {
      if (_textKeys.contains(k)) return;
      if (parseNumber(c.text)?.isNaN ?? false) {
        errors[k] = 'Enter a valid number';
      }
    });
    for (var i = 0; i < _stones.length; i++) {
      if (parseNumber(_stones[i].weight.text)?.isNaN ?? false) {
        errors['stone.$i.weight'] = 'Enter a valid number';
      }
      if (parseNumber(_stones[i].rate.text)?.isNaN ?? false) {
        errors['stone.$i.rate'] = 'Enter a valid number';
      }
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      errors['purity'] = 'Save gold rates first';
    } else {
      for (final issue in AppScope.read(
        context,
      ).engine.validate(input, snapshot.perGram)) {
        errors.putIfAbsent(issue.field, () => issue.message);
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fix ${errors.length} '
            '${errors.length == 1 ? 'field' : 'fields'} highlighted in red',
          ),
        ),
      );
      return;
    }
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          input: input,
          ratesSnapshot: snapshot!,
          recordId: _recordId,
          source: _isScan ? 'scan' : 'manual',
          openedFromForm: true,
        ),
      ),
    );
    if (id != null && mounted) setState(() => _recordId = id);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final current = state.rates;
    final snapshot = _snapshot;
    final usingOldRates =
        snapshot != null && current != null && snapshot != current;
    final rate = _purity == null ? null : snapshot?.rateFor(_purity!);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recordId != null
              ? 'Edit Saved Item'
              : _isScan
              ? 'Review Scanned Details'
              : 'Manual Jewellery Entry',
        ),
        actions: const [RatesAction()],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ResponsiveBody(
            shrinkHeight: true,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('calculate'),
                onPressed: _calculate,
                icon: const Icon(Icons.calculate_outlined),
                label: Text(
                  _uncertain.isEmpty
                      ? 'Calculate Cost'
                      : 'Confirm ${_uncertain.length} highlighted '
                            '${_uncertain.length == 1 ? 'field' : 'fields'}',
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            key: const Key('formList'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (_isScan && (_uncertain.isNotEmpty || _missing.isNotEmpty))
                _hintBox(
                  'Highlighted fields were unclear or missing on the tag. '
                  'Check them against the physical tag before calculating.',
                ),
              if (usingOldRates)
                _hintBox(
                  'Priced with gold rates saved ${formatDateTime(snapshot.updatedAt)}.',
                  action: TextButton(
                    onPressed: () => setState(() => _snapshot = current),
                    child: const Text('Use current rates'),
                  ),
                ),

              // ---------------------------------------------- identification
              const SectionTitle('Jewellery identification'),
              _textField('tagNumber', 'Tag number / item code'),
              const SizedBox(height: 12),
              _textField('itemName', 'Item name / description'),

              // --------------------------------------------- weight & purity
              const SizedBox(height: 14),
              const SectionTitle('Weight and purity'),
              Text(
                'Gold purity',
                style: TextStyle(
                  color: _errors['purity'] != null
                      ? AppColors.error
                      : AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<Purity>(
                  key: const Key('purity'),
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    for (final p in Purity.values)
                      ButtonSegment(
                        value: p,
                        label: Text(
                          p.label,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  selected: {?_purity},
                  onSelectionChanged: (s) {
                    _purity = s.isEmpty ? null : s.first;
                    _edited('purity');
                  },
                ),
              ),
              if (_stateOf('purity') != FieldState.normal)
                FlagNote(
                  state: _stateOf('purity'),
                  note:
                      _uncertain['purity'] ??
                      'Purity not found on tag — select it',
                  onConfirm: _purity == null ? null : () => _confirm('purity'),
                ),
              if (_errors['purity'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _errors['purity']!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  rate == null
                      ? 'Select purity to apply the saved gold rate'
                      : 'Applied gold rate (${_purity!.label}): ${formatInr(rate)} per gram'
                            '${snapshot!.quotedPerGrams == 1 ? '' : ' (${formatInr(snapshot.quotedRateFor(_purity!)!)} / ${snapshot.quoteUnit})'}',
                  key: const Key('appliedRate'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
              _num2(
                'goldWeight',
                'Gold weight',
                'g',
                hint: 'Metal weight used for pricing',
              ),
              const SizedBox(height: 12),
              _num2(
                'grossWeight',
                'Gross jewellery weight (optional)',
                'g',
                hint: 'For reference only — not used in pricing',
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 6),
              const Text(
                'Gold weight is used as entered. Stone weight is never '
                'subtracted automatically.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),

              // ------------------------------------------- diamonds & stones
              const SizedBox(height: 14),
              const SectionTitle('Diamonds & stones'),
              for (var i = 0; i < _stones.length; i++) ...[
                _stoneCard(i),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('addDiamond'),
                    onPressed: () => _addStone(StoneKind.diamond),
                    icon: const Icon(Icons.add),
                    label: const Text('Diamond line'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _addStone(StoneKind.stone),
                    icon: const Icon(Icons.add),
                    label: const Text('Other stone line'),
                  ),
                ],
              ),
              _weightBalance(),
              _excludeSwitch(
                'Exclude diamond value',
                _excludeDiamond,
                (v) => setState(() {
                  _excludeDiamond = v;
                  _errors.removeWhere((k, _) => k.endsWith('.rate'));
                }),
              ),
              _excludeSwitch(
                'Exclude other stone value',
                _excludeStone,
                (v) => setState(() {
                  _excludeStone = v;
                  _errors.removeWhere((k, _) => k.endsWith('.rate'));
                }),
              ),

              // ------------------------------------------------ pricing inputs
              const SizedBox(height: 14),
              const SectionTitle('Pricing inputs'),
              const Text(
                'Making charges',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<MakingMethod>(
                  key: const Key('makingMethod'),
                  showSelectedIcon: false,
                  segments: [
                    for (final m in MakingMethod.values)
                      ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {_making},
                  onSelectionChanged: (s) {
                    _making = s.first;
                    _edited('makingValue');
                  },
                ),
              ),
              const SizedBox(height: 10),
              switch (_making) {
                MakingMethod.perGram => _num2(
                  'makingValue',
                  'Making charges',
                  '/ g × gold wt',
                  prefix: '₹ ',
                ),
                MakingMethod.fixed => _num2(
                  'makingValue',
                  'Making charges',
                  null,
                  prefix: '₹ ',
                ),
                MakingMethod.percentOfGold => _num2(
                  'makingValue',
                  'Making charges',
                  '% of gold value',
                ),
              },
              const SizedBox(height: 10),
              const Text(
                'Wastage (one method only)',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<WastageMethod>(
                  key: const Key('wastageMethod'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: WastageMethod.none,
                      label: Text('None'),
                    ),
                    ButtonSegment(
                      value: WastageMethod.percent,
                      label: Text('%'),
                    ),
                    ButtonSegment(
                      value: WastageMethod.weight,
                      label: Text('Grams'),
                    ),
                  ],
                  selected: {_wastage},
                  onSelectionChanged: (s) {
                    setState(() {
                      // The method choice resolves any "% or grams?" doubt.
                      _uncertain.remove('wastagePercent');
                      _uncertain.remove('wastageWeight');
                      _wastage = s.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (_wastage == WastageMethod.percent)
                _num2('wastagePercent', 'Wastage', '% of gold value'),
              if (_wastage == WastageMethod.weight)
                _num2('wastageWeight', 'Wastage weight', 'g × gold rate'),

              // -------------------------------------------------------- GST
              const SizedBox(height: 14),
              const SectionTitle('GST'),
              _num2(
                'gstRate',
                'GST rate',
                '%',
                hint: 'As per your invoicing rules',
              ),
              const SizedBox(height: 10),
              const Text(
                'Taxable components',
                style: TextStyle(color: AppColors.muted),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final comp in PriceComponent.values)
                    FilterChip(
                      label: Text(comp.label),
                      selected: _taxable.contains(comp),
                      selectedColor: AppColors.goldSoft,
                      onSelected: (v) => setState(() {
                        v ? _taxable.add(comp) : _taxable.remove(comp);
                        _errors.remove('gstRate');
                      }),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Separate GST rate for making charges'),
                value: _separateMakingGst,
                onChanged: (v) => setState(() => _separateMakingGst = v),
              ),
              if (_separateMakingGst)
                _num2('gstMakingRate', 'GST rate on making charges', '%'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hintBox(String text, {Widget? action}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.warnSoft,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: AppColors.warn),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
        ?action,
      ],
    ),
  );

  Widget _stoneCard(int i) {
    final row = _stones[i];
    final kindKey = 'stone.$i.kind';
    final excluded = row.kind == StoneKind.diamond
        ? _excludeDiamond
        : _excludeStone;
    return Card(
      key: ValueKey(row),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      row.label ?? 'Line ${i + 1}',
                      if (row.code != null) 'tag rate ${row.code}',
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove line',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _removeStone(i),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<StoneKind>(
                key: Key(kindKey),
                showSelectedIcon: false,
                segments: [
                  for (final k in StoneKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {row.kind},
                onSelectionChanged: (sel) {
                  row.kind = sel.first;
                  _edited(kindKey);
                },
              ),
            ),
            if (_stateOf(kindKey) != FieldState.normal)
              FlagNote(
                state: _stateOf(kindKey),
                note: _uncertain[kindKey],
                onConfirm: () => _confirm(kindKey),
              ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _stoneField(i, 'weight', row.weight, 'Weight', 'ct'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _stoneField(
                      i,
                      'rate',
                      row.rate,
                      'Rate',
                      '/ ct',
                      prefix: '₹ ',
                      enabled: !excluded,
                    ),
                  ),
                ],
              ),
            ),
            if (row.code != null && row.codeRate != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  'Rate from tag: ${row.code} × '
                  '${formatPercent(AppScope.of(context).tagRateMultiplier)} = '
                  '${formatInr(row.codeRate!)}/ct',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stoneField(
    int i,
    String part,
    TextEditingController controller,
    String label,
    String unit, {
    String? prefix,
    bool enabled = true,
  }) {
    final key = 'stone.$i.$part';
    return NumberField(
      fieldKey: Key(key),
      controller: controller,
      label: label,
      unit: unit,
      prefix: prefix,
      enabled: enabled,
      errorText: _errors[key],
      state: _stateOf(key),
      note: _uncertain[key],
      onConfirm: () => _confirm(key),
      onChanged: (_) => _edited(key),
    );
  }

  /// Live check: gross − gold weight should equal stone carats × 0.2 g.
  Widget _weightBalance() {
    final gross = parseNumber(_c['grossWeight']!.text);
    final net = parseNumber(_c['goldWeight']!.text);
    final ct = _stones.fold<double>(
      0,
      (a, r) => a + (parseNumber(r.weight.text) ?? 0),
    );
    if (gross == null || net == null || gross.isNaN || net.isNaN || ct <= 0) {
      return const SizedBox(height: 8);
    }
    final b = WeightBalance(grossG: gross, netG: net, stonesCt: ct);
    final ok = b.balances;
    return Container(
      key: const Key('weightBalance'),
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? AppColors.okSoft : AppColors.warnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info_outline,
            color: ok ? AppColors.ok : AppColors.warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? 'Weights balance: gross ${gross.toStringAsFixed(3)} g − gold '
                        '${net.toStringAsFixed(3)} g = ${b.differenceG.toStringAsFixed(3)} g '
                        '= ${ct.toStringAsFixed(2)} ct of stones'
                  : 'Weights do not balance: gross − gold = '
                        '${b.differenceG.toStringAsFixed(3)} g, but stones '
                        '${ct.toStringAsFixed(2)} ct = ${b.stonesG.toStringAsFixed(3)} g. '
                        'Check the weights (other materials can also explain a gap).',
            ),
          ),
        ],
      ),
    );
  }

  Widget _excludeSwitch(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: onChanged,
  );

  Widget _textField(String key, String label) {
    final st = _stateOf(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: Key(key),
          controller: _c[key],
          onChanged: (_) => _edited(key),
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            labelText: label,
            errorText: _errors[key],
            fillColor: st == FieldState.normal
                ? AppColors.surface
                : AppColors.warnSoft,
          ),
        ),
        if (st != FieldState.normal)
          FlagNote(
            state: st,
            note: _uncertain[key],
            onConfirm: () => _confirm(key),
          ),
      ],
    );
  }

  Widget _num2(
    String key,
    String label,
    String? unit, {
    String? prefix,
    String? hint,
    bool enabled = true,
  }) => NumberField(
    fieldKey: Key(key),
    controller: _c[key]!,
    label: label,
    unit: unit,
    prefix: prefix,
    hint: hint,
    enabled: enabled,
    errorText: _errors[key],
    state: _stateOf(key),
    note: _missing.contains(key)
        ? 'Not found on tag — enter it from the tag'
        : _uncertain[key],
    onConfirm: () => _confirm(key),
    onChanged: (_) => _edited(key),
  );
}

/// Editable state for one diamond/stone line.
class _StoneRow {
  _StoneRow({required this.kind, this.label, this.code, this.codeRate});

  factory _StoneRow.from(StoneLine l, {double? codeRate}) =>
      _StoneRow(kind: l.kind, label: l.label, code: l.code, codeRate: codeRate)
        ..weight.text = formatInput(l.weightCt)
        ..rate.text = formatInput(l.ratePerCt);

  StoneKind kind;
  final String? label;
  final String? code;

  /// ₹/ct derived from [code] (code × multiplier), shown as a hint.
  final double? codeRate;
  final weight = TextEditingController();
  final rate = TextEditingController();

  String get displayName => label ?? kind.label;

  StoneLine toLine() => StoneLine(
    kind: kind,
    label: label,
    code: code,
    weightCt: parseNumber(weight.text),
    ratePerCt: parseNumber(rate.text),
  );

  void dispose() {
    weight.dispose();
    rate.dispose();
  }
}
