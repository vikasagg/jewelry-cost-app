import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../models/gold_rates.dart';
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
  bool _saving = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final rates = AppScope.read(context).rates;
    if (rates != null) {
      for (final p in Purity.values) {
        _controllers[p]!.text = formatInput(rates.rateFor(p));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
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
    if (_errors.values.any((e) => e != null)) return;
    setState(() => _saving = true);
    final state = AppScope.read(context);
    final rates = GoldRates(
      perGram: {
        for (final p in Purity.values) p: parseNumber(_controllers[p]!.text)!,
      },
      updatedAt: state.now(),
    );
    await state.saveRates(rates);
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
        title: Text(widget.firstRun ? 'Welcome' : 'Gold Rate Settings'),
        automaticallyImplyLeading: !widget.firstRun,
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
                'Enter the current rate per gram in ₹ for each purity. '
                'The rate matching the item\'s purity is used directly — no extra '
                'purity adjustment is applied.',
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
              const SizedBox(height: 20),
              for (final p in Purity.values) ...[
                NumberField(
                  fieldKey: Key('rate_${p.name}'),
                  controller: _controllers[p]!,
                  label: '${p.label} Gold rate',
                  prefix: '₹ ',
                  unit: '/ gram',
                  errorText: _errors[p],
                  onChanged: (_) {
                    if (_errors[p] != null) setState(() => _errors[p] = null);
                  },
                ),
                if (rates?.rateFor(p) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text(
                      'Saved: ${formatInr(rates!.rateFor(p)!)}/g',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 8),
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
