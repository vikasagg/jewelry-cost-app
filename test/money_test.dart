import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_cost/core/money.dart';

void main() {
  group('Indian currency formatting', () {
    test('groups lakhs and crores', () {
      expect(formatInr(125450), '₹1,25,450.00');
      expect(formatInr(99395), '₹99,395.00');
      expect(formatInr(12345678.9), '₹1,23,45,678.90');
      expect(formatInr(999), '₹999.00');
      expect(formatInr(0), '₹0.00');
      expect(formatInr(1000), '₹1,000.00');
      expect(formatInr(100000), '₹1,00,000.00');
    });

    test('rounds half away from zero to the paisa', () {
      expect(toPaise(1.005), 101);
      expect(toPaise(2.675), 268);
      expect(toPaise(10.004), 1000);
      expect(roundRupees(0.125), 0.13);
      expect(formatInr(1234.565), '₹1,234.57');
    });

    test('negative amounts', () {
      expect(formatPaise(-12345600), '-₹1,23,456.00');
    });

    test('can omit symbol', () {
      expect(formatInr(125450, symbol: false), '1,25,450.00');
    });
  });
}
