import 'package:flutter/material.dart';

import '../theme.dart';

/// Bottom sheet with a large numeric keypad for entering a whole-number
/// quantity. Returns the number, or null when cancelled.
Future<int?> showNumericKeypad(
  BuildContext context, {
  required String title,
  String? subtitle,
  int? initial,
  int maxDigits = 5,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _Keypad(
    title: title,
    subtitle: subtitle,
    initial: initial,
    maxDigits: maxDigits,
  ),
);

class _Keypad extends StatefulWidget {
  const _Keypad({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.maxDigits,
  });
  final String title;
  final String? subtitle;
  final int? initial;
  final int maxDigits;

  @override
  State<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<_Keypad> {
  late String _text = widget.initial?.toString() ?? '';

  void _tap(String k) => setState(() {
    switch (k) {
      case '⌫':
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      case 'C':
        _text = '';
      default:
        if (_text == '0') _text = '';
        if (_text.length < widget.maxDigits) _text += k;
    }
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String k) => Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 56,
        child: FilledButton.tonal(
          key: Key('key_$k'),
          style: FilledButton.styleFrom(
            backgroundColor: k == 'C' || k == '⌫'
                ? AppColors.tile
                : AppColors.goldSoft,
            foregroundColor: AppColors.ink,
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
                Container(
                  key: const Key('keypadDisplay'),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _text.isEmpty ? '—' : _text,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['C', '0', '⌫'],
                ])
                  Row(children: [for (final k in row) Expanded(child: key(k))]),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('keypadDone'),
                  onPressed: _text.isEmpty
                      ? null
                      : () => Navigator.pop(context, int.parse(_text)),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
