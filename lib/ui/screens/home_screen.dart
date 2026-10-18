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
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
            children: [
              const BrandLogo(size: 34, stacked: true),
              const SizedBox(height: 8),
              const Text(
                'Calculate  •  Count  •  Share',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 32),
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
  Widget build(BuildContext context) => GoldCard(
    onTap: onTap,
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFFF7EEDB))),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}
