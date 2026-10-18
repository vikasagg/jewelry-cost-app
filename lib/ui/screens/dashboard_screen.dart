import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../branding.dart';
import '../../core/money.dart';
import '../../models/purity.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
        title: const BrandHeader(size: 34),
        actions: const [HistoryAction(), RatesAction()],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // Primary action
              Material(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  key: const Key('scanTag'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _open(context, const ScanScreen()),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          color: Colors.white,
                          size: 30,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan Jewellery Tag',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Capture a tag and read weights & purity',
                                style: TextStyle(color: Color(0xFFF7EEDB)),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // History, right under the main action.
              OutlinedButton.icon(
                key: const Key('historyButton'),
                onPressed: () => _open(context, const HistoryScreen()),
                icon: const Icon(Icons.history),
                label: Text('History  ($historyCount saved)'),
              ),
              const SizedBox(height: 12),
              TileGrid(
                minTileWidth: 200,
                children: [
                  _ActionTile(
                    key: const Key('manualEntry'),
                    icon: Icons.edit_note,
                    title: 'Manual Jewellery Entry',
                    onTap: () => _open(context, const DetailsFormScreen()),
                  ),
                  _ActionTile(
                    icon: Icons.currency_rupee,
                    title: 'Gold Rate Settings',
                    onTap: () =>
                        _open(context, const RateSetupScreen(firstRun: false)),
                  ),
                  _ActionTile(
                    key: const Key('dailyStockSummary'),
                    icon: Icons.inventory_2_outlined,
                    title: 'Daily Stock Summary',
                    onTap: () => _open(context, const StockHomeScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SectionTitle(
                'Current gold rates',
                trailing: TextButton(
                  onPressed: () =>
                      _open(context, const RateSetupScreen(firstRun: false)),
                  child: const Text('Update'),
                ),
              ),
              if (rates != null) ...[
                TileGrid(
                  minTileWidth: 140,
                  children: [
                    for (final p in Purity.values.reversed)
                      StatTile(
                        label: '${p.label} per ${rates.quoteUnit}',
                        value: formatInr(rates.quotedRateFor(p) ?? 0),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Last updated ${formatDateTime(rates.updatedAt)}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.goldDeep),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
