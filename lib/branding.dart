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

/// Monogram + shop name (+ optional subtitle), used on the cost estimate
/// shared to customers and as a page header.
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
                fontFamily: serifFont,
                fontSize: size * 0.6,
                fontWeight: FontWeight.w600,
                color: AppColors.goldDeep,
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

/// Gold diamond outline over the serif shop name, as on the splash and
/// dashboard mock-ups.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 22, this.stacked = false});

  /// Font size of the name.
  final double size;

  /// Diamond above the name (splash) instead of beside it (app bar).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.diamond_outlined,
      color: AppColors.gold,
      size: stacked ? size * 2.6 : size * 1.4,
    );
    final name = Text(
      Brand.name,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: serifFont,
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        height: 1.1,
      ),
    );
    return stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [icon, const SizedBox(height: 10), name],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 8),
              Flexible(child: name),
            ],
          );
  }
}
