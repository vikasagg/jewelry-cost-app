import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'branding.dart';
import 'data/key_value_store.dart';
import 'data/secure_hive_store.dart';
import 'ui/screens/home_screen.dart';
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
  final state = AppState(store, defaultServerUrl: _sameOriginServer());
  state.stockSync.start();
  runApp(JewelleryCostApp(state: state));
}

/// When the web app is opened from the shop PC itself (PocketBase serves
/// it from pb_public, e.g. http://192.168.1.10:8090), that PC is the
/// database server.
String? _sameOriginServer() {
  if (!kIsWeb) return null;
  final u = Uri.base;
  if (u.host.isEmpty || u.host.endsWith('github.io')) return null;
  return u.origin;
}

class JewelleryCostApp extends StatelessWidget {
  const JewelleryCostApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Compact UI: all text 25% smaller (on top of the phone's own
      // font-size setting) so a screen fits with little scrolling.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * uiTextScale),
          ),
          child: child!,
        );
      },
      // Choose Price Calculator or Stock Reconciliation first.
      home: const HomeScreen(),
    ),
  );
}
