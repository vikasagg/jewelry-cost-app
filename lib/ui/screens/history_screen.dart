import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../models/calculation_record.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'details_form_screen.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();

  /// Decoded photo thumbnails by record id (decoded once, not per build).
  final _photos = <String, Uint8List?>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(CalculationRecord r) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ResultScreen(
        input: r.input,
        ratesSnapshot: r.ratesSnapshot,
        recordId: r.id,
        source: r.source,
        savedAt: r.updatedAt,
      ),
    ),
  );

  void _edit(CalculationRecord r) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DetailsFormScreen(
        initial: r.input,
        ratesSnapshot: r.ratesSnapshot,
        recordId: r.id,
      ),
    ),
  );

  Future<void> _delete(CalculationRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(
          '${r.input.displayName}\n${formatPaise(r.result.totalPaise)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppScope.read(context).deleteCalculation(r.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final records = state.history.search(_search.text);
    final total = state.history.all().length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        actions: const [RatesAction()],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  key: const Key('historySearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search tag number or description',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            total == 0
                                ? 'No saved calculations yet.\nUse "Save to History" on a cost summary.'
                                : 'No records match "${_search.text}".',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _RecordCard(
                          record: records[i],
                          photo: _photos.putIfAbsent(
                            records[i].id,
                            () =>
                                AppScope.read(context).imageFor(records[i].id),
                          ),
                          onOpen: () => _open(records[i]),
                          onEdit: () => _edit(records[i]),
                          onDelete: () => _delete(records[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.photo,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });
  final CalculationRecord record;
  final Uint8List? photo;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = record.result;
    final i = record.input;
    final details = [
      '${i.goldWeight!.toStringAsFixed(3)} g',
      if (i.diamondWeight > 0) '${i.diamondWeight.toStringAsFixed(2)} ct',
      if (i.stoneWeight > 0) '${formatPercent(i.stoneWeight)} pcs',
      if (i.polkiWeight > 0) 'Polki ${i.polkiWeight.toStringAsFixed(2)} ct',
    ];
    const muted = TextStyle(color: AppColors.muted, fontSize: 13);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: photo == null
                    ? Container(
                        width: 60,
                        height: 60,
                        color: AppColors.goldSoft,
                        child: const Icon(
                          Icons.diamond_outlined,
                          color: AppColors.gold,
                        ),
                      )
                    : Image.memory(
                        photo!,
                        key: Key('historyPhoto_${record.id}'),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        cacheWidth: 180, // decode at thumbnail size
                        gaplessPlayback: true,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            i.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          formatPaise(r.totalPaise),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r.purity.label} Gold',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          DateFormat('d MMM yyyy').format(record.createdAt),
                          style: muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(details.join(' | '), style: muted),
                        ),
                        Text(
                          DateFormat('h:mm a').format(record.createdAt),
                          style: muted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('historyMenu_${record.id}'),
                icon: const Icon(Icons.more_vert, color: AppColors.muted),
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
