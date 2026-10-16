import 'package:flutter/material.dart';

import 'ui/theme.dart';

/// Shop branding used across the app, the shared estimate image and text.
class Brand {
  static const name = 'Damiyaas Jewelers';
  static const tagline = 'Jewellery Cost Calculator';
  static const monogram = 'D';
}

/// Gold circular monogram.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC9A55A), AppColors.goldDeep],
      ),
    ),
    child: Text(
      Brand.monogram,
      // Fixed size: the monogram must not scale with the text setting.
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.55,
        fontWeight: FontWeight.w700,
        fontFamily: 'serif',
      ),
    ),
  );
}

/// Monogram + shop name (+ optional subtitle), used on the dashboard and on
/// the cost estimate shared to customers.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.subtitle = Brand.tagline, this.size = 40});
  final String subtitle;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      BrandMark(size: size),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Brand.name,
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.w700,
                color: AppColors.goldDeep,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}
