import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../screens/history_screen.dart';
import '../screens/rate_setup_screen.dart';
import '../theme.dart';

/// Parses user-typed numbers ("1,25,000", "₹ 7000", " 10.25 "). Returns null
/// when empty and NaN when not a number, so callers can tell them apart.
double? parseNumber(String text) {
  final t = text.replaceAll(RegExp(r'[₹,\s]'), '');
  if (t.isEmpty) return null;
  return double.tryParse(t) ?? double.nan;
}

String formatInput(double? v, {int? decimals}) {
  if (v == null) return '';
  if (decimals != null) return v.toStringAsFixed(decimals);
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

final _dateFmt = DateFormat('d MMM yyyy, h:mm a');
String formatDateTime(DateTime d) => _dateFmt.format(d);

/// AppBar action that opens the saved estimates (history) from any screen.
class HistoryAction extends StatelessWidget {
  const HistoryAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('historyAction'),
    tooltip: 'History',
    icon: const Icon(Icons.history),
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
  );
}

/// AppBar action that opens gold rate settings from any screen.
class RatesAction extends StatelessWidget {
  const RatesAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Gold rate settings',
    icon: const Icon(Icons.currency_rupee),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RateSetupScreen(firstRun: false)),
    ),
  );
}

/// Centres content with a comfortable max width on tablets/web.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.shrinkHeight = false,
  });
  final Widget child;
  final double maxWidth;

  /// Size to the child's height (for bottom bars) instead of filling.
  final bool shrinkHeight;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: shrinkHeight ? 1 : null,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Grey tile with a small label and a large value (as in the sample UI).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.icon,
  });
  final String label;
  final String value;
  final bool highlight;

  /// Optional small icon shown before the label.
  final Widget? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: highlight ? AppColors.goldSoft : AppColors.tile,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Lays children out two per row (one per row on very narrow screens).
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 150});
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = (c.maxWidth / minTileWidth).floor().clamp(1, 4);
      final perRow = cols >= 4 ? 4 : (cols >= 2 ? 2 : 1);
      const gap = 10.0;
      final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}

enum FieldState { normal, uncertain, missing }

/// Large numeric input with unit suffix and scan-confidence highlighting.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.unit,
    this.prefix,
    this.hint,
    this.errorText,
    this.state = FieldState.normal,
    this.note,
    this.onConfirm,
    this.onChanged,
    this.enabled = true,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String? unit;
  final String? prefix;
  final String? hint;
  final String? errorText;
  final FieldState state;
  final String? note;
  final VoidCallback? onConfirm;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final flagged = state != FieldState.normal;
    final color = state == FieldState.missing
        ? AppColors.error
        : AppColors.warn;
    final border = flagged
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: color, width: 2),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹ ]')),
          ],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: errorText,
            errorMaxLines: 3,
            prefixText: prefix,
            // suffixIcon (unlike suffixText) stays visible when empty, so the
            // unit is always clear.
            suffixIcon: unit == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 14, left: 4),
                    child: Text(
                      unit!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            filled: true,
            fillColor: flagged ? AppColors.warnSoft : AppColors.surface,
            enabledBorder: border,
            focusedBorder: border,
          ),
        ),
        if (flagged) FlagNote(note: note, state: state, onConfirm: onConfirm),
      ],
    );
  }
}

class FlagNote extends StatelessWidget {
  const FlagNote({super.key, this.note, required this.state, this.onConfirm});
  final String? note;
  final FieldState state;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final color = state == FieldState.missing
        ? AppColors.error
        : AppColors.warn;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            state == FieldState.missing
                ? Icons.error_outline
                : Icons.help_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              note ??
                  (state == FieldState.missing
                      ? 'Not found on tag — enter manually'
                      : 'Unclear on tag — please confirm'),
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
          if (state == FieldState.uncertain && onConfirm != null)
            TextButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Confirm'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ok,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

/// A label/value row for cost breakdowns.
class BreakdownRow extends StatelessWidget {
  const BreakdownRow({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.bold = false,
    this.valueKey,
    this.icon,
  });
  final String label;
  final String value;
  final String? caption;
  final bool bold;
  final Key? valueKey;

  /// Optional small icon shown before the label.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 15,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: bold ? AppColors.ink : AppColors.muted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(padding: const EdgeInsets.only(top: 1), child: icon),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      caption!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold icon on a soft gold rounded square (mock-up style).
class IconSquare extends StatelessWidget {
  const IconSquare({super.key, required this.icon, this.size = 36});
  final Widget icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    child: IconTheme(
      data: IconThemeData(color: AppColors.gold, size: size * 0.55),
      child: icon,
    ),
  );
}

/// Gold-gradient card for the primary action or a total.
class GoldCard extends StatelessWidget {
  const GoldCard({super.key, required this.child, this.onTap, this.padding});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: AppColors.goldGradient,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: AppColors.goldDeep.withValues(alpha: 0.25),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Menu row: icon square, title, subtitle and a chevron.
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    // Soft beige tile with a light shadow, as in the design.
    color: const Color(0xFFF8F0E1),
    elevation: 1.5,
    shadowColor: AppColors.goldDeep.withValues(alpha: 0.25),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            IconSquare(icon: Icon(icon), size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// Label/value line with a small leading icon (details lists).
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueKey,
  });
  final Widget icon;
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: 22, child: icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Text(
          value,
          key: valueKey,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
