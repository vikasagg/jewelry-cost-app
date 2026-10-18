import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../stock/stock_models.dart';
import '../../../stock/stock_report.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'stock_count_screen.dart';
import 'stock_dialogs.dart';

/// Daily Stock Summary: today's count plus the stock history. Physical
/// counts only — nothing here touches prices, gold rates or estimates.
class StockHomeScreen extends StatelessWidget {
  const StockHomeScreen({super.key});

  Future<void> _open(BuildContext context, String date) async {
    final book = AppScope.read(context).stock;
    final day = await book.open(date);
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StockCountScreen(initial: day)));
  }

  @override
  Widget build(BuildContext context) {
    final book = AppScope.of(context).stock;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final days = book.all();
        final today = book.byDate(book.today);
        final past = days.where((d) => d.date != book.today).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Daily Stock Summary'),
            actions: [
              IconButton(
                key: const Key('managerPin'),
                tooltip: 'Manager PIN',
                icon: const Icon(Icons.admin_panel_settings_outlined),
                onPressed: () => showSetPinDialog(context, book),
              ),
            ],
          ),
          body: SafeArea(
            child: ResponsiveBody(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Text(
                    'Physical stock count only — prices, gold rates and '
                    'cost estimates are not affected.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  _TodayCard(
                    date: book.today,
                    day: today,
                    onOpen: () => _open(context, book.today),
                  ),
                  if (!book.hasManagerPin) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warnSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, color: AppColors.warn),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Set a manager PIN — needed to approve counts '
                              'and stock adjustments.',
                            ),
                          ),
                          TextButton(
                            onPressed: () => showSetPinDialog(context, book),
                            child: const Text('Set PIN'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const SectionTitle('Stock history'),
                  if (past.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No earlier counts yet.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  for (final d in past)
                    _DayTile(day: d, onTap: () => _open(context, d.date)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.date,
    required this.day,
    required this.onOpen,
  });
  final String date;
  final DailyStock? day;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Material(
      color: AppColors.gold,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const Key('openTodayStock'),
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d == null
                          ? 'Start today\'s count'
                          : d.status == StockStatus.draft
                          ? 'Continue today\'s count'
                          : 'Today\'s count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d == null
                          ? stockDateLabel(date)
                          : '${stockDateLabel(date)} · ${d.status.label}\n'
                                'Physical ${d.totalCount} · '
                                '${differenceLabel(d.totalDifference)}',
                      style: const TextStyle(color: Color(0xFFF7EEDB)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.onTap});
  final DailyStock day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final diff = day.totalDifference;
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          stockDateLabel(day.date),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${day.employee.isEmpty ? '—' : day.employee} · '
          'Expected ${day.totalExpected} · Physical ${day.totalCount}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(status: day.status),
            const SizedBox(height: 4),
            Text(
              diff == 0 ? 'Matched' : differenceLabel(diff),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: diff == 0 ? AppColors.ok : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small coloured label for a day's status.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      StockStatus.verified => (AppColors.okSoft, AppColors.ok),
      StockStatus.submitted => (AppColors.warnSoft, AppColors.warn),
      StockStatus.draft => (AppColors.tile, AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
