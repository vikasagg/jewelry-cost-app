import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_state.dart';
import '../../../metals/metal_prices.dart';
import '../../../models/gold_rates.dart';
import '../../../models/purity.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Gold & Silver: record the day's gold (24K per 10 g) and silver (per kg)
/// prices, see the history with day-to-day changes, and share on
/// WhatsApp. Today's gold rate can also update the Price Calculator.
class MetalPricesScreen extends StatefulWidget {
  const MetalPricesScreen({super.key});

  @override
  State<MetalPricesScreen> createState() => _MetalPricesScreenState();
}

class _MetalPricesScreenState extends State<MetalPricesScreen> {
  late final _book = AppScope.read(context).metalPrices;
  late String _date = _book.today;
  final _gold = TextEditingController();
  final _silver = TextEditingController();
  bool _useInCalculator = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gold.dispose();
    _silver.dispose();
    super.dispose();
  }

  static String _num(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  /// Fills the form for [_date]: its record, else (for today) the
  /// calculator's gold rate and the last silver price.
  void _load() {
    final p = _book.byDate(_date);
    if (p != null) {
      _gold.text = _num(p.gold24Per10g);
      _silver.text = _num(p.silverPerKg);
      return;
    }
    final latest = _book.latest;
    final calc = AppScope.read(context).rates?.perGram[Purity.k24];
    _gold.text = _num(calc != null ? calc * 10 : latest.gold24Per10g);
    _silver.text = _num(latest.silverPerKg);
  }

  double? _value(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '').trim());
    return v == null || v <= 0 ? null : v;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDate() async {
    final fmt = DateFormat('yyyy-MM-dd');
    final picked = await showDatePicker(
      context: context,
      initialDate: fmt.parse(_date),
      firstDate: DateTime(2020),
      lastDate: fmt.parse(_book.today),
      helpText: 'Rates for',
    );
    if (picked == null) return;
    setState(() {
      _date = fmt.format(picked);
      _load();
    });
  }

  Future<void> _save() async {
    final gold = _value(_gold), silver = _value(_silver);
    if (gold == null && silver == null) {
      _snack('Enter the gold or silver price');
      return;
    }
    final state = AppScope.read(context);
    await _book.save(_date, gold24Per10g: gold, silverPerKg: silver);
    final toCalc = gold != null && _date == _book.today && _useInCalculator;
    if (toCalc) {
      await state.saveRates(
        GoldRates.fromBase24(
          perGram24: gold / 10,
          updatedAt: state.now(),
          quotedPerGrams: 10,
        ),
      );
    }
    if (!mounted) return;
    setState(() {});
    _snack(
      toCalc
          ? 'Saved · Price Calculator now uses this gold rate'
          : 'Saved rates for ${_book.byDate(_date)!.dateLabel}',
    );
  }

  Future<void> _share(MetalPrice p) async {
    final url = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(metalPriceText(p))}',
    );
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) _snack('Could not open WhatsApp');
  }

  @override
  Widget build(BuildContext context) {
    final gold = _value(_gold), silver = _value(_silver);
    final saved = _book.byDate(_date);
    final history = _book.all();
    return Scaffold(
      appBar: AppBar(title: const Text('Gold & Silver')),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              OutlinedButton.icon(
                key: const Key('metalDate'),
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  '${_date == _book.today ? 'Today · ' : ''}'
                  '${DateFormat('d MMM yyyy').format(DateFormat('yyyy-MM-dd').parse(_date))}',
                ),
              ),
              const SizedBox(height: 12),
              _PriceCard(
                title: 'Gold',
                icon: Icons.circle,
                iconColor: AppColors.gold,
                field: TextField(
                  key: const Key('gold24Field'),
                  controller: _gold,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '24K price per 10 g',
                    prefixText: '₹ ',
                  ),
                ),
                rows: [
                  for (final p in Purity.values.reversed.skip(1))
                    (
                      '${p.label} (${p.percentOf24}%)',
                      gold == null
                          ? '—'
                          : '${rupees(gold * p.percentOf24 / 100)} / 10 g',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _PriceCard(
                title: 'Silver',
                icon: Icons.circle,
                iconColor: const Color(0xFFA7A9AC),
                field: TextField(
                  key: const Key('silverField'),
                  controller: _silver,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Price per kg',
                    prefixText: '₹ ',
                  ),
                ),
                rows: [
                  ('Per 10 g', silver == null ? '—' : rupees(silver / 100)),
                  ('Per g', silver == null ? '—' : rupees(silver / 1000)),
                ],
              ),
              if (_date == _book.today)
                CheckboxListTile(
                  key: const Key('useInCalculator'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _useInCalculator,
                  onChanged: (v) => setState(() => _useInCalculator = v!),
                  title: const Text(
                    'Also use this gold rate in the Price Calculator',
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('saveMetalPrices'),
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('shareMetalPrices'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: saved == null ? null : () => _share(saved),
                      icon: const Icon(Icons.send),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SectionTitle('History (${history.length})'),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No prices recorded yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              for (final p in history)
                _HistoryTile(
                  key: Key('metalHistory_${p.date}'),
                  price: p,
                  previous: _book.before(p.date),
                  selected: p.date == _date,
                  onTap: () => setState(() {
                    _date = p.date;
                    _load();
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.field,
    required this.rows,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget field;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          field,
          const SizedBox(height: 8),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                  Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.price,
    required this.previous,
    required this.selected,
    required this.onTap,
  });
  final MetalPrice price;
  final MetalPrice? previous;
  final bool selected;
  final VoidCallback onTap;

  Widget _change(double? now, double? before) {
    if (now == null || before == null || now == before) {
      return const SizedBox.shrink();
    }
    final up = now > before;
    return Text(
      ' ${up ? '▲' : '▼'} ${rupees((now - before).abs())}',
      style: TextStyle(
        color: up ? AppColors.ok : AppColors.error,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = price;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.gold : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.dateLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Gold 24K ${p.gold24Per10g == null ? '—' : '${rupees(p.gold24Per10g!)} / 10 g'}',
                  ),
                  _change(p.gold24Per10g, previous?.gold24Per10g),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Silver ${p.silverPerKg == null ? '—' : '${rupees(p.silverPerKg!)} / kg'}',
                  ),
                  _change(p.silverPerKg, previous?.silverPerKg),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
