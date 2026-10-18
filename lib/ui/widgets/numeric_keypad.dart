import 'package:flutter/material.dart';

import '../../stock/stock_models.dart';
import '../theme.dart';

/// Result of the counting keypad: the total and how it was added up.
typedef KeypadResult = ({int value, String expression});

/// Bottom sheet with a large calculator-style keypad (digits, + and −) for
/// counting pieces, e.g. 5 + 3 + 2 − 1. Every entry stays visible with the
/// running total. [onChanged] reports the working as it is typed (so the
/// caller can auto-save it). Returns null when cancelled.
Future<KeypadResult?> showCountKeypad(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? initialExpression,
  ValueChanged<String>? onChanged,
}) => showModalBottomSheet<KeypadResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _Keypad(
    title: title,
    subtitle: subtitle,
    initial: initialExpression ?? '',
    onChanged: onChanged,
  ),
);

class _Keypad extends StatefulWidget {
  const _Keypad({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.onChanged,
  });
  final String title;
  final String? subtitle;
  final String initial;
  final ValueChanged<String>? onChanged;

  @override
  State<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<_Keypad> {
  late String _text = widget.initial;

  static const _maxDigits = 5;

  CountExpression get _expr => CountExpression(_text);

  void _tap(String k) {
    setState(() {
      switch (k) {
        case '⌫':
          if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
        case 'C':
          _text = '';
        case '+' || '−':
          final op = k == '+' ? '+' : '-';
          if (_text.isEmpty) {
            if (op == '-') _text = '-';
          } else if (RegExp(r'[+-]$').hasMatch(_text)) {
            // Pressing another sign replaces the last one.
            _text = _text.substring(0, _text.length - 1) + op;
          } else {
            _text += op;
          }
        default:
          final last = RegExp(r'(\d+)$').firstMatch(_text)?.group(1) ?? '';
          if (last == '0') {
            _text = _text.substring(0, _text.length - 1); // no leading zeros
          } else if (last.length >= _maxDigits) {
            return;
          }
          _text += k;
      }
    });
    widget.onChanged?.call(_text);
  }

  @override
  Widget build(BuildContext context) {
    final expr = _expr;
    final total = expr.value;
    final negative = total != null && total < 0;
    final canFinish = expr.isComplete && total != null && !negative;

    Widget key(String k, {Color? bg}) => Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 54,
        child: FilledButton.tonal(
          key: Key('key_$k'),
          style: FilledButton.styleFrom(
            backgroundColor: bg ?? AppColors.goldSoft,
            foregroundColor: AppColors.ink,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => _tap(k),
          child: Text(
            k,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                const SizedBox(height: 10),
                // The "tape": every entry, then the total.
                Container(
                  key: const Key('keypadDisplay'),
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _text.isEmpty ? 'Enter pieces, use + / −' : expr.pretty,
                        key: const Key('keypadWorking'),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 18,
                          color: _text.isEmpty
                              ? AppColors.muted
                              : AppColors.ink,
                        ),
                      ),
                      Text(
                        total == null ? '= —' : '= $total',
                        key: const Key('keypadTotal'),
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          color: negative ? AppColors.error : AppColors.ink,
                        ),
                      ),
                      if (negative)
                        const Text(
                          'Total cannot be below 0',
                          style: TextStyle(color: AppColors.error),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final row in const [
                  ['7', '8', '9', '⌫'],
                  ['4', '5', '6', '−'],
                  ['1', '2', '3', '+'],
                ])
                  Row(
                    children: [
                      for (final k in row)
                        Expanded(
                          child: key(
                            k,
                            bg: '⌫+−'.contains(k) ? AppColors.tile : null,
                          ),
                        ),
                    ],
                  ),
                Row(
                  children: [
                    Expanded(child: key('C', bg: AppColors.tile)),
                    Expanded(child: key('0')),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            key: const Key('keypadDone'),
                            onPressed: canFinish
                                ? () => Navigator.pop(context, (
                                    value: total,
                                    expression: _text,
                                  ))
                                : null,
                            icon: const Icon(Icons.check),
                            label: Text(
                              total == null || !canFinish
                                  ? 'Done'
                                  : 'Done = $total',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
