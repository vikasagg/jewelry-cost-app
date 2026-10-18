import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_state.dart';
import '../../core/money.dart';
import '../../models/calculation_record.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Picks the scanned products that go on a bill. Pops with the chosen
/// records in the order they were ticked, or null when cancelled.
class BillItemsScreen extends StatefulWidget {
  const BillItemsScreen({super.key, this.initialIds = const []});

  /// Records ticked when the screen opens (the current estimate, or the
  /// products already on a bill being edited).
  final List<String> initialIds;

  @override
  State<BillItemsScreen> createState() => _BillItemsScreenState();
}

class _BillItemsScreenState extends State<BillItemsScreen> {
  final _search = TextEditingController();
  late final List<String> _picked = [...widget.initialIds];
  final _photos = <String, Uint8List?>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(
    () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.history.all();
    final byId = {for (final r in all) r.id: r};
    final chosen = [
      for (final id in _picked)
        if (byId[id] != null) byId[id]!,
    ];
    final shown = state.history.search(_search.text);
    final total = chosen.fold(0, (a, r) => a + r.result.totalPaise);
    return Scaffold(
      appBar: AppBar(title: const Text('Select products')),
      body: SafeArea(
        child: ResponsiveBody(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  key: const Key('billItemsSearch'),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  'Tick every product the customer is buying.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty
                              ? 'No saved products yet. Scan a tag first.'
                              : 'No products match "${_search.text}".',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, k) {
                          final r = shown[k];
                          return _ProductTile(
                            record: r,
                            photo: _photos.putIfAbsent(
                              r.id,
                              () => state.imageFor(r.id),
                            ),
                            billNo: state.billFor(r.id)?.billNo,
                            picked: _picked.contains(r.id),
                            onTap: () => _toggle(r.id),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('billItemsNext'),
                    onPressed: chosen.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(chosen),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      chosen.isEmpty
                          ? 'Select at least one product'
                          : 'Next · ${chosen.length} '
                                'product${chosen.length == 1 ? '' : 's'} · '
                                '${formatPaise(total)}',
                    ),
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

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.record,
    required this.photo,
    required this.billNo,
    required this.picked,
    required this.onTap,
  });
  final CalculationRecord record;
  final Uint8List? photo;
  final String? billNo;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = record.input, r = record.result;
    const muted = TextStyle(color: AppColors.muted, fontSize: 13);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: picked ? AppColors.gold : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        key: Key('billItem_${record.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(value: picked, onChanged: (_) => onTap()),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: photo == null
                    ? Container(
                        width: 48,
                        height: 48,
                        color: AppColors.goldSoft,
                        child: const Icon(
                          Icons.diamond_outlined,
                          color: AppColors.gold,
                        ),
                      )
                    : Image.memory(
                        photo!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${r.purity.label} · ${i.goldWeight!.toStringAsFixed(3)} g'
                      ' · ${DateFormat('d MMM, h:mm a').format(record.updatedAt)}',
                      style: muted,
                    ),
                    if (billNo != null)
                      Text(
                        'On bill $billNo',
                        style: const TextStyle(
                          color: AppColors.goldDeep,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                formatPaise(r.totalPaise),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
