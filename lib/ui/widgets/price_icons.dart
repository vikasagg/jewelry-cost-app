import 'package:flutter/material.dart';

import '../theme.dart';

/// Small icons that label each line of a cost estimate.
abstract final class PriceIcons {
  static const double size = 18;

  static Widget _icon(IconData d) =>
      Icon(d, size: size, color: AppColors.goldDeep);

  static Widget get gold => const GoldBarIcon();
  static Widget get purity => _icon(Icons.workspace_premium_outlined);
  static Widget get weight => _icon(Icons.scale_outlined);
  static Widget get grossWeight => _icon(Icons.monitor_weight_outlined);
  static Widget get tag => _icon(Icons.local_offer_outlined);
  static Widget get rate => _icon(Icons.currency_rupee);
  static Widget get diamond => _icon(Icons.diamond_outlined);
  static Widget get stone => _icon(Icons.hexagon_outlined);
  static Widget get polki => _icon(Icons.auto_awesome_outlined);
  static Widget get labour => _icon(Icons.handyman_outlined);
  static Widget get wastage => _icon(Icons.content_cut);
  static Widget get subtotal => _icon(Icons.calculate_outlined);
  static Widget get gst => _icon(Icons.receipt_long_outlined);
}

/// A small gold ingot (Material has no gold icon).
class GoldBarIcon extends StatelessWidget {
  const GoldBarIcon({super.key, this.size = PriceIcons.size});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GoldBarPainter());
}

class _GoldBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    // Trapezoid ingot seen from the front, with a lighter top face.
    final body = Path()
      ..moveTo(w * 0.05, h * 0.80)
      ..lineTo(w * 0.22, h * 0.36)
      ..lineTo(w * 0.78, h * 0.36)
      ..lineTo(w * 0.95, h * 0.80)
      ..close();
    final top = Path()
      ..moveTo(w * 0.22, h * 0.36)
      ..lineTo(w * 0.32, h * 0.22)
      ..lineTo(w * 0.68, h * 0.22)
      ..lineTo(w * 0.78, h * 0.36)
      ..close();
    final rect = Offset.zero & s;
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE2C26B), Color(0xFFA8843A)],
        ).createShader(rect),
    );
    canvas.drawPath(top, Paint()..color = const Color(0xFFF3DD9A));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.06
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.goldDeep;
    canvas
      ..drawPath(body, edge)
      ..drawPath(top, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
