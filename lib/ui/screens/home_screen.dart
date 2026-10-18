import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../models/purity.dart';
import '../../stock/stock_models.dart';
import '../theme.dart';
import 'dashboard_screen.dart';
import 'rate_setup_screen.dart';
import 'stock/stock_home_screen.dart';

/// "Royal Night" palette for the home screen only.
abstract final class _Night {
  static const espressoTop = Color(0xFF4A3418);
  static const espresso = Color(0xFF24180D);
  static const espressoDeep = Color(0xFF140E08);
  static const gold = Color(0xFFE9C77B);
  static const goldPale = Color(0xFFF6DFA4);
  static const sand = Color(0xFFC9B590);
  static const text = Color(0xFFF4EBDD);
  static const faint = Color(0xFF9C8B6E);
}

/// First screen: choose between the price calculator and daily stock
/// reconciliation (the two never share data). Dark espresso background
/// with a gold glow and a faint diamond lattice, like a velvet tray.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rates = state.rates;
    final book = state.stock;
    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _Night.espressoDeep,
        body: Stack(
          children: [
            const Positioned.fill(child: _Backdrop()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    // Fill the screen (cards at the bottom); scroll on
                    // very short screens.
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        // Content stays at most 520 px wide on tablets.
                        padding: EdgeInsets.fromLTRB(
                          c.maxWidth > 568 ? (c.maxWidth - 520) / 2 : 24,
                          16,
                          c.maxWidth > 568 ? (c.maxWidth - 520) / 2 : 24,
                          24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TopBar(
                              date: state.now(),
                              rate24: rates == null
                                  ? null
                                  : '24K ${formatInr(rates.quotedRateFor(Purity.k24) ?? 0).replaceAll('.00', '')} / ${rates.quoteUnit}',
                            ),
                            const SizedBox(height: 56),
                            const _Crest(),
                            const Spacer(),
                            const SizedBox(height: 40),
                            _ModeCard(
                              key: const Key('openPriceCalculator'),
                              filled: true,
                              icon: Icons.calculate_outlined,
                              title: 'Price Calculator',
                              subtitle: 'Scan a tag · estimate in seconds',
                              onTap: () => open(
                                state.hasRates
                                    ? const DashboardScreen()
                                    : const RateSetupScreen(firstRun: true),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ListenableBuilder(
                              listenable: book,
                              builder: (context, _) => _ModeCard(
                                key: const Key('openStock'),
                                filled: false,
                                icon: Icons.inventory_2_outlined,
                                title: 'Stock Reconciliation',
                                subtitle: _stockStatus(book.byDate(book.today)),
                                onTap: () => open(const StockHomeScreen()),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Works offline · Data stays on this phone',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _Night.faint,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Today's count at a glance, e.g. "Today: 9 of 14 counted · Draft".
  static String _stockStatus(DailyStock? d) {
    if (d == null) return 'Today: not started';
    final counted = stockItems.where((i) => d.counts.containsKey(i.code));
    return 'Today: ${counted.length} of ${stockItems.length} counted · '
        '${d.status.label}';
  }
}

/// Espresso gradient, gold glow and a faint diamond lattice.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -0.62),
        radius: 1.25,
        colors: [_Night.espressoTop, _Night.espresso, _Night.espressoDeep],
        stops: [0, 0.45, 1],
      ),
    ),
    child: CustomPaint(painter: _LatticePainter()),
  );
}

class _LatticePainter extends CustomPainter {
  const _LatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _Night.gold.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    const gap = 28.0;
    final span = size.width + size.height;
    for (var d = -size.height; d < span; d += gap) {
      canvas
        ..drawLine(Offset(d, 0), Offset(d + size.height, size.height), line)
        ..drawLine(Offset(d, size.height), Offset(d + size.height, 0), line);
    }
    // Soft glow behind the crest.
    final c = Offset(size.width / 2, size.height * 0.30);
    canvas.drawCircle(
      c,
      170,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _Night.gold.withValues(alpha: 0.30),
            _Night.gold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: 170)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.date, required this.rate24});
  final DateTime date;
  final String? rate24;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          DateFormat('EEEE, d MMM').format(date),
          style: const TextStyle(color: _Night.sand, fontSize: 16),
        ),
      ),
      if (rate24 != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _Night.gold.withValues(alpha: 0.45)),
          ),
          child: Text(
            rate24!,
            key: const Key('homeRate24'),
            style: const TextStyle(color: _Night.gold, fontSize: 15),
          ),
        ),
    ],
  );
}

/// Diamond, "Damiyaas", "JEWELERS" and the tagline.
class _Crest extends StatelessWidget {
  const _Crest();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(
        width: 84,
        height: 84,
        child: CustomPaint(painter: _DiamondPainter()),
      ),
      SizedBox(height: 18),
      Text(
        'Damiyaas',
        style: TextStyle(
          fontFamily: serifFont,
          fontSize: 58,
          fontWeight: FontWeight.w600,
          color: _Night.goldPale,
          height: 1.1,
        ),
      ),
      SizedBox(height: 4),
      Text(
        'JEWELERS',
        style: TextStyle(color: _Night.sand, fontSize: 17, letterSpacing: 9),
      ),
      SizedBox(height: 18),
      SizedBox(
        width: 64,
        child: Divider(color: _Night.gold, thickness: 1, height: 1),
      ),
      SizedBox(height: 14),
      Text(
        'Estimate · Count · Share',
        style: TextStyle(color: _Night.sand, fontSize: 18),
      ),
    ],
  );
}

/// Gold outline of a cut diamond.
class _DiamondPainter extends CustomPainter {
  const _DiamondPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = _Night.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.035
      ..strokeJoin = StrokeJoin.round;
    double x(double v) => s.width * v / 64;
    double y(double v) => s.height * v / 64;
    final outline = Path()
      ..moveTo(x(16), y(10))
      ..lineTo(x(48), y(10))
      ..lineTo(x(58), y(24))
      ..lineTo(x(32), y(56))
      ..lineTo(x(6), y(24))
      ..close();
    final facets = Path()
      ..moveTo(x(6), y(24))
      ..lineTo(x(58), y(24))
      ..moveTo(x(24), y(10))
      ..lineTo(x(18), y(24))
      ..lineTo(x(32), y(56))
      ..lineTo(x(46), y(24))
      ..lineTo(x(40), y(10));
    canvas
      ..drawPath(outline, p)
      ..drawPath(facets, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A choice card: solid gold ([filled]) or glass with a gold border.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.filled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool filled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : _Night.text;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: filled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD7AE5C), AppColors.gold, Color(0xFF7E5D21)],
                stops: [0, 0.6, 1],
              )
            : null,
        color: filled ? null : Colors.white.withValues(alpha: 0.06),
        border: filled
            ? null
            : Border.all(color: _Night.gold.withValues(alpha: 0.35)),
        boxShadow: filled
            ? const [
                BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: filled
                        ? Colors.white.withValues(alpha: 0.18)
                        : _Night.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: filled ? Colors.white : _Night.gold,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: fg,
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: filled
                              ? Colors.white.withValues(alpha: 0.88)
                              : _Night.sand,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: filled ? Colors.white : _Night.gold,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
