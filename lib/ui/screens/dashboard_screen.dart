import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../branding.dart';
import '../../core/money.dart';
import '../../models/gold_rates.dart';
import '../../models/purity.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bill_screen.dart';
import 'details_form_screen.dart';
import 'history_screen.dart';
import 'rate_setup_screen.dart';
import 'scan_screen.dart';
import 'stock/stock_home_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rates = state.rates;
    final historyCount = state.history.all().length;
    return Scaffold(
      appBar: AppBar(
        title: const BrandLogo(size: 20),
        actions: const [HistoryAction(), RatesAction()],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (rates != null)
                _RatesCard(
                  rates: rates,
                  onEdit: () =>
                      _open(context, const RateSetupScreen(firstRun: false)),
                ),
              const SizedBox(height: 14),
              // Primary action
              GoldCard(
                key: const Key('scanTag'),
                onTap: () => _open(context, const ScanScreen()),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.photo_camera_outlined, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan Jewellery Tag',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Use camera to read tag details',
                            style: TextStyle(color: Color(0xFFF7EEDB)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MenuTile(
                key: const Key('manualEntry'),
                icon: Icons.edit_outlined,
                title: 'Manual Jewellery Entry',
                subtitle: 'Enter details manually',
                onTap: () => _open(context, const DetailsFormScreen()),
              ),
              const SizedBox(height: 10),
              MenuTile(
                icon: Icons.bar_chart_rounded,
                title: 'Gold Rate Settings',
                subtitle: 'Update current gold rates',
                onTap: () =>
                    _open(context, const RateSetupScreen(firstRun: false)),
              ),
              const SizedBox(height: 10),
              MenuTile(
                key: const Key('historyButton'),
                icon: Icons.history,
                title: 'Scan History',
                subtitle:
                    'View and manage past calculations '
                    '($historyCount saved)',
                onTap: () => _open(context, const HistoryScreen()),
              ),
              const SizedBox(height: 10),
              MenuTile(
                key: const Key('newBill'),
                icon: Icons.receipt_long_outlined,
                title: 'New Bill',
                subtitle: 'Pick scanned products and bill the customer',
                onTap: () => startBill(context),
              ),
              const SizedBox(height: 10),
              MenuTile(
                key: const Key('dailyStockSummary'),
                icon: Icons.inventory_2_outlined,
                title: 'Daily Stock Summary',
                subtitle: 'Count stock and share the daily report',
                onTap: () => _open(context, const StockHomeScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Current Gold Rates" card: every purity with its rate.
class _RatesCard extends StatelessWidget {
  const _RatesCard({required this.rates, required this.onEdit});
  final GoldRates rates;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Current Gold Rates ',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '(per ${rates.quoteUnit})',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          const SizedBox(height: 4),
          // One row of purities with dividers, as in the design.
          IntrinsicHeight(
            child: Row(
              children: [
                for (final (n, p) in Purity.values.reversed.indexed) ...[
                  if (n > 0)
                    const VerticalDivider(width: 1, color: AppColors.line),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          p.label,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.goldDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            child: Text(
                              formatInr(
                                rates.quotedRateFor(p) ?? 0,
                              ).replaceAll('.00', ''),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 18),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Last updated: ${formatDateTime(rates.updatedAt)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
