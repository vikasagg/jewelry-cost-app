import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'data/key_value_store.dart';
import 'data/repositories.dart';
import 'models/calculation_record.dart';
import 'models/gold_rates.dart';
import 'models/jewellery_input.dart';
import 'pricing/pricing_engine.dart';

/// App-wide state: current gold rates, pricing defaults and history.
class AppState extends ChangeNotifier {
  AppState(KeyValueStore store, {DateTime Function()? clock})
    : _rates = RatesRepository(store),
      _defaults = PricingDefaultsRepository(store),
      history = HistoryRepository(store),
      _clock = clock ?? DateTime.now {
    _current = _rates.load();
  }

  final RatesRepository _rates;
  final PricingDefaultsRepository _defaults;
  final HistoryRepository history;
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
  double get tagRateMultiplier => _defaults.tagRateMultiplier;

  Future<void> setTagRateMultiplier(double value) async {
    await _defaults.setTagRateMultiplier(value);
    notifyListeners();
  }

  /// Saves (or updates, when [existingId] is given) a calculation.
  Future<CalculationRecord> saveCalculation({
    required JewelleryInput input,
    required GoldRates ratesSnapshot,
    required PricingResult result,
    String? existingId,
    String source = 'manual',
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
    notifyListeners();
    return record;
  }

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
