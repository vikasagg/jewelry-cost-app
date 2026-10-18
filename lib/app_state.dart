import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'data/key_value_store.dart';
import 'data/repositories.dart';
import 'models/calculation_record.dart';
import 'models/gold_rates.dart';
import 'models/jewellery_input.dart';
import 'pricing/pricing_engine.dart';
import 'stock/stock_book.dart';

/// App-wide state: current gold rates, pricing defaults and history.
class AppState extends ChangeNotifier {
  AppState(KeyValueStore store, {DateTime Function()? clock})
    : _rates = RatesRepository(store),
      _defaults = PricingDefaultsRepository(store),
      history = HistoryRepository(store),
      stock = StockBook(store, clock: clock),
      _clock = clock ?? DateTime.now {
    _current = _rates.load();
  }

  final RatesRepository _rates;
  final PricingDefaultsRepository _defaults;
  final HistoryRepository history;

  /// Daily physical stock counts — separate from pricing and its history.
  final StockBook stock;
  final DateTime Function() _clock;
  final engine = const PricingEngine();

  GoldRates? _current;
  GoldRates? get rates => _current;
  bool get hasRates => _current?.isComplete ?? false;

  DateTime now() => _clock();

  Future<void> saveRates(GoldRates rates) async {
    await _rates.save(rates);
    _current = rates;
    notifyListeners();
  }

  JewelleryInput get pricingDefaults => _defaults.load();

  /// ₹/ct to pre-fill for a stone line: tag rate code × multiplier.
  double? stoneRateFor(StoneKind kind, String? code) =>
      _defaults.rateFor(kind, code);

  /// Multiplier from the rate code printed on tags to ₹ per carat.
  double tagRateMultiplier(StoneKind kind) => _defaults.tagRateMultiplier(kind);

  Future<void> setTagRateMultiplier(StoneKind kind, double value) async {
    await _defaults.setTagRateMultiplier(kind, value);
    notifyListeners();
  }

  /// Next automatic tag number for a new scan/entry, e.g. "DJ-0001".
  String get nextTagNumber => _defaults.nextTagNumber;

  /// Saves (or updates, when [existingId] is given) a calculation.
  Future<CalculationRecord> saveCalculation({
    required JewelleryInput input,
    required GoldRates ratesSnapshot,
    required PricingResult result,
    String? existingId,
    String source = 'manual',
    Uint8List? image,
  }) async {
    final now = _clock();
    final existing = existingId == null ? null : history.byId(existingId);
    final record = existing != null
        ? existing.copyWith(
            updatedAt: now,
            input: input,
            ratesSnapshot: ratesSnapshot,
            result: result,
          )
        : CalculationRecord(
            id: const Uuid().v4(),
            createdAt: now,
            updatedAt: now,
            input: input,
            ratesSnapshot: ratesSnapshot,
            result: result,
            source: source,
          );
    await history.save(record);
    // A re-save without a new photo keeps the one already stored.
    if (image != null) await history.saveImage(record.id, image);
    await _defaults.recordTagNumber(input.tagNumber);
    notifyListeners();
    return record;
  }

  /// Thumbnail of the scanned tag saved with a calculation.
  Uint8List? imageFor(String id) => history.imageFor(id);

  Future<void> deleteCalculation(String id) async {
    await history.delete(id);
    notifyListeners();
  }
}

/// Exposes [AppState] to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
