import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../branding.dart';
import '../../core/money.dart';
import '../../models/gold_rates.dart';
import '../../models/jewellery_input.dart';
import '../../models/purity.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart';

/// First-run (and settings) screen for per-gram gold rates.
class RateSetupScreen extends StatefulWidget {
  const RateSetupScreen({super.key, required this.firstRun});
  final bool firstRun;

  @override
  State<RateSetupScreen> createState() => _RateSetupScreenState();
}

class _RateSetupScreenState extends State<RateSetupScreen> {
  final _controllers = {
    for (final p in Purity.values) p: TextEditingController(),
  };
  final _errors = <Purity, String?>{};
  final _multipliers = {
    for (final k in StoneKind.values) k: TextEditingController(),
  };
  final _multiplierErrors = <StoneKind, String?>{};
  bool _saving = false;
  bool _loaded = false;

  /// Rates are typed per this many grams (10 by default, as commonly quoted
  /// in India); stored internally per 1 g.
  int _perGrams = 10;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    for (final k in StoneKind.values) {
      _multipliers[k]!.text = formatPercent(
        AppScope.read(context).tagRateMultiplier(k),
      );
    }
    final rates = AppScope.read(context).rates;
    if (rates != null) {
      _perGrams = rates.quotedPerGrams;
      for (final p in Purity.values) {
        _controllers[p]!.text = formatInput(rates.quotedRateFor(p));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _multipliers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(String text) {
    final v = parseNumber(text);
    if (v == null) return 'Required';
    if (v.isNaN) return 'Enter a number';
    if (v <= 0) return 'Must be greater than 0';
    if (v > 10000000) return 'Rate looks too high';
    return null;
  }

  Future<void> _save() async {
    setState(() {
      for (final p in Purity.values) {
        _errors[p] = _validate(_controllers[p]!.text);
      }
    });
    final m = {
      for (final k in StoneKind.values) k: parseNumber(_multipliers[k]!.text),
    };
    setState(() {
      for (final k in StoneKind.values) {
        final v = m[k];
        _multiplierErrors[k] = (v == null || v.isNaN || v <= 0)
            ? 'Enter a number greater than 0'
            : null;
      }
    });
    if (_errors.values.any((e) => e != null) ||
        _multiplierErrors.values.any((e) => e != null)) {
      return;
    }
    setState(() => _saving = true);
    final state = AppScope.read(context);
    final rates = GoldRates(
      perGram: {
        for (final p in Purity.values)
          p: parseNumber(_controllers[p]!.text)! / _perGrams,
      },
      updatedAt: state.now(),
      quotedPerGrams: _perGrams,
    );
    await state.saveRates(rates);
    for (final k in StoneKind.values) {
      await state.setTagRateMultiplier(k, m[k]!);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gold rates updated')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rates = AppScope.of(context).rates;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.firstRun ? 'Welcome to ${Brand.name}' : 'Gold Rate Settings',
        ),
        automaticallyImplyLeading: !widget.firstRun,
        actions: const [HistoryAction()],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 560,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Today\'s gold rates',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter today\'s rate in ₹ for each purity. Weights are entered '
                'in grams exactly as printed on the tag; the app converts the '
                'rate to per gram. No extra purity adjustment is applied.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
              if (rates != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.goldSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: AppColors.goldDeep),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Last updated ${formatDateTime(rates.updatedAt)}',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Rates entered per',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  key: const Key('ratePerGrams'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 10, label: Text('10 grams')),
                    ButtonSegment(value: 1, label: Text('1 gram')),
                  ],
                  selected: {_perGrams},
                  onSelectionChanged: (v) =>
                      setState(() => _perGrams = v.first),
                ),
              ),
              const SizedBox(height: 10),
              for (final p in Purity.values) ...[
                NumberField(
                  fieldKey: Key('rate_${p.name}'),
                  controller: _controllers[p]!,
                  label: '${p.label} Gold rate',
                  prefix: '₹ ',
                  unit: _perGrams == 1 ? '/ gram' : '/ $_perGrams g',
                  errorText: _errors[p],
                  onChanged: (_) {
                    if (_errors[p] != null) setState(() => _errors[p] = null);
                  },
                ),
                if (rates?.rateFor(p) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text(
                      'Saved: ${formatInr(rates!.quotedRateFor(p)!)} / '
                      '${rates.quoteUnit}'
                      '${rates.quotedPerGrams == 1 ? '' : ' (${formatInr(rates.rateFor(p)!)}/g)'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 8),
              const Text(
                'Rates printed on tags',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'A tag line like DIA\\0.38\\700 has a rate code (700). '
                '₹ per carat = code × multiplier.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              for (final k in StoneKind.values) ...[
                NumberField(
                  fieldKey: Key('tagRateMultiplier_${k.name}'),
                  controller: _multipliers[k]!,
                  label: '${k.label} rate multiplier',
                  unit: '×',
                  errorText: _multiplierErrors[k],
                  onChanged: (_) => setState(() => _multiplierErrors[k] = null),
                ),
                Builder(
                  builder: (_) {
                    final v = parseNumber(_multipliers[k]!.text);
                    final code = k == StoneKind.stone ? 600 : 700;
                    return Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        top: 2,
                        bottom: 8,
                      ),
                      child: Text(
                        v == null || v.isNaN
                            ? ''
                            : 'Example: code $code → ${formatInr(code * v)} per carat',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('saveRates'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(
                  widget.firstRun ? 'Save Rates & Continue' : 'Save Rates',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
