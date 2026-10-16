/// Money helpers. All amounts are handled internally as integer paise so that
/// sums never drift because of floating point error.
library;

/// Converts a rupee amount (double) to paise, rounding half away from zero.
int toPaise(double rupees) {
  final scaled = rupees * 100;
  // A tiny nudge absorbs representation error such as 1.005 * 100 = 100.4999…
  final nudge = scaled >= 0 ? 1e-6 : -1e-6;
  return (scaled + nudge).round();
}

/// Rounds a rupee amount to 2 decimals (half away from zero).
double roundRupees(double rupees) => toPaise(rupees) / 100;

/// Formats paise using Indian digit grouping, e.g. 12545000 -> ₹1,25,450.00.
String formatPaise(int paise, {bool symbol = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final grouped = groupIndian(rupees.toString());
  return '${negative ? '-' : ''}${symbol ? '₹' : ''}$grouped.$fraction';
}

/// Formats a rupee amount using Indian grouping.
String formatInr(double rupees, {bool symbol = true}) =>
    formatPaise(toPaise(rupees), symbol: symbol);

/// Applies Indian grouping (last 3 digits, then pairs) to a digit string.
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Formats a weight/number with fixed decimals, trimming nothing.
String formatFixed(double value, int decimals) =>
    value.toStringAsFixed(decimals);

/// Strips a trailing ".0"/zeros for compact display of percentages.
String formatPercent(double value) {
  final s = value.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}
