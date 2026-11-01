import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'sales_register_screen.dart';

/// Reports: today's sales register (more reports can be added here).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reports')),
    body: SafeArea(
      child: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            MenuTile(
              key: const Key('todaysSales'),
              icon: Icons.receipt_long_outlined,
              title: "Today's Sales",
              subtitle: 'Photo of the register page → clean customer register',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesRegisterScreen()),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
