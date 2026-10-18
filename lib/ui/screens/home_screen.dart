import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../branding.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart';
import 'rate_setup_screen.dart';
import 'stock/stock_home_screen.dart';

/// First screen: choose between the price calculator and daily stock
/// reconciliation. The two never share data.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            children: [
              const BrandHeader(
                subtitle: 'Choose what you want to do',
                size: 48,
              ),
              const SizedBox(height: 28),
              _ModeCard(
                key: const Key('openPriceCalculator'),
                icon: Icons.calculate_outlined,
                title: 'Price Calculator',
                subtitle: 'Scan a tag and estimate the jewellery cost',
                onTap: () => open(
                  state.hasRates
                      ? const DashboardScreen()
                      : const RateSetupScreen(firstRun: true),
                ),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                key: const Key('openStock'),
                icon: Icons.inventory_2_outlined,
                title: 'Stock Reconciliation',
                subtitle: 'Daily physical stock count and summary',
                onTap: () => open(const StockHomeScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    shadowColor: AppColors.gold.withValues(alpha: 0.3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 32, color: AppColors.goldDeep),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.goldDeep),
          ],
        ),
      ),
    ),
  );
}
