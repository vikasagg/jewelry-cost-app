import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data/key_value_store.dart';
import 'data/secure_hive_store.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/rate_setup_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyValueStore store;
  try {
    store = await SecureHiveStore.open('jewellery_cost_data');
  } catch (e) {
    // Never block the shop counter: fall back to a session-only store.
    debugPrint('Local storage unavailable, using memory store: $e');
    store = MemoryStore();
  }
  runApp(JewelleryCostApp(state: AppState(store)));
}

class JewelleryCostApp extends StatelessWidget {
  const JewelleryCostApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: MaterialApp(
      title: 'Smart Jewellery Cost Calculator',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: state.hasRates
          ? const DashboardScreen()
          : const RateSetupScreen(firstRun: true),
    ),
  );
}
