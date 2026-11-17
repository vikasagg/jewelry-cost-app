import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_state.dart';
import '../../../core/money.dart';
import '../../../stock/stock_import.dart';
import '../../../stock/stock_sync.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'stock_dialogs.dart';

/// The shop's stock item by item, from the stock export (Excel), kept on
/// the shop PC: search by Tag No, and import a new export.
class StockItemsScreen extends StatefulWidget {
  const StockItemsScreen({super.key, this.pickExport});

  /// For tests: returns the chosen .xlsx file's bytes.
  final Future<Uint8List?> Function()? pickExport;

  @override
  State<StockItemsScreen> createState() => _StockItemsScreenState();
}

class _StockItemsScreenState extends State<StockItemsScreen> {
  late final StockSync _sync = AppScope.read(context).stockSync;
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  int _total = 0;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _load() async {
    final server = _sync.server;
    if (server == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await server.findStockItems(_search.text);
      if (!mounted) return;
      setState(() {
        _total = r.total;
        _items = r.items;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Shop PC not reachable');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _pick() async {
    if (widget.pickExport != null) return widget.pickExport!();
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Stock export (.xlsx)',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (files.isEmpty) return null;
    return files.first.readAsBytes();
  }

  Future<void> _import() async {
    final server = _sync.server;
    if (server == null) return;
    final bytes = await _pick();
    if (bytes == null || !mounted) return;
    final StockExport export;
    try {
      export = parseStockExport(bytes);
    } on FormatException catch (e) {
      _snack('This is not a stock export: ${e.message}');
      return;
    } catch (_) {
      _snack('This file could not be read. Choose the .xlsx stock export.');
      return;
    }
    if (export.items.isEmpty) {
      _snack('No items with a Tag No in this file');
      return;
    }
    final who = await _confirm(export);
    if (who == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final r = await server.importStock(
        export.items,
        name: who.name,
        pin: who.pin,
      );
      _snack(
        'Imported: ${r.created} new, ${r.updated} updated'
        '${r.suppliers == 0 ? '' : ', ${r.suppliers} new suppliers'}',
      );
      await _load();
    } on StockServerException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Shop PC not reachable — nothing was imported');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows what will be imported and asks who is importing (with PIN).
  Future<({String name, String pin})?> _confirm(StockExport e) {
    final staff = _sync.staff;
    final pin = TextEditingController();
    var name = staff.length == 1 ? staff.first.name : '';
    return showDialog<({String name, String pin})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Import stock export'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${e.items.length} items (by Tag No) · '
                    '${e.suppliers.length} suppliers · '
                    '${e.withoutSupplier} without supplier',
                    key: const Key('importSummary'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (e.duplicateTags.isNotEmpty || e.skipped > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          if (e.duplicateTags.isNotEmpty)
                            'Repeated Tag No (last row kept): '
                                '${e.duplicateTags.take(8).join(', ')}',
                          if (e.skipped > 0) '${e.skipped} rows without Tag No',
                        ].join('\n'),
                        style: const TextStyle(color: AppColors.warn),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Items already on the PC are updated; new suppliers get '
                    'the address Delhi and mobile 9717000000 (edit them in '
                    'the admin panel).',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (staff.isEmpty)
                    TextField(
                      key: const Key('importName'),
                      onChanged: (v) => name = v.trim(),
                      decoration: const InputDecoration(labelText: 'Your name'),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('importName'),
                      initialValue: name.isEmpty ? null : name,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      items: [
                        for (final s in staff)
                          DropdownMenuItem(value: s.name, child: Text(s.name)),
                      ],
                      onChanged: (v) => setLocal(() => name = v ?? ''),
                    ),
                  TextField(
                    key: const Key('importPin'),
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(labelText: 'Your PIN'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('importOk'),
              onPressed: () {
                if (name.isEmpty || pin.text.length < 4) return;
                Navigator.pop(context, (name: name, pin: pin.text));
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  void _details(Map<String, dynamic> it) {
    final supplier = (it['expand'] as Map?)?['supplier'] as Map?;
    String w(String k) {
      final v = it[k];
      return v is num && v != 0 ? '${v.toStringAsFixed(3)} g' : '';
    }

    String n(String k) {
      final v = it[k];
      return v is num && v != 0 ? formatInr(v.toDouble()) : '';
    }

    final rows = <(String, String)>[
      ('Item', '${it['item_name'] ?? ''}'),
      ('Pieces', '${(it['pcs'] as num?)?.toInt() ?? ''}'),
      ('Gross weight', w('gross_wt')),
      ('Net weight', w('net_wt')),
      ('Gold weight', w('gold_wt')),
      (
        'Diamond weight',
        (it['dia_wt'] as num? ?? 0) == 0 ? '' : '${it['dia_wt']} ct',
      ),
      ('Stone weight', w('stone_wt')),
      ('Labour / g', n('labour_per_gm')),
      ('Labour (fixed)', n('labour_rs')),
      (
        'Diamond rate / value',
        (it['dia_value'] as num? ?? 0) == 0
            ? ''
            : '${n('dia_rate')} · ${n('dia_value')}',
      ),
      (
        'Stone rate / value',
        (it['stn_value'] as num? ?? 0) == 0
            ? ''
            : '${n('stn_rate')} · ${n('stn_value')}',
      ),
      ('MRP', n('mrp')),
      ('Design', '${it['design'] ?? ''}'),
      ('Remarks', '${it['remarks'] ?? ''}'),
      ('Size', '${it['size'] ?? ''}'),
      ('Hallmark', it['hallmark'] == true ? 'Yes' : ''),
      ('Entry date', '${it['entry_date'] ?? ''}'.split(' ').first),
      (
        'Supplier',
        supplier == null
            ? '${it['supplier_name'] ?? ''}'
            : '${supplier['name']} · ${supplier['mobile']} · ${supplier['address']}',
      ),
      ('Status', '${it['status'] ?? ''}'.replaceAll('_', ' ')),
    ].where((r) => r.$2.trim().isNotEmpty).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${it['tag_no']}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          k,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _sync.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Stock items')),
      body: SafeArea(
        child: ResponsiveBody(
          child: !connected
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Stock items are kept on the shop PC. Connect it first.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await showServerDialog(context, _sync);
                          if (mounted) setState(() {});
                          await _load();
                        },
                        child: const Text('Set up the shop PC'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    TextField(
                      key: const Key('stockItemSearch'),
                      controller: _search,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 350),
                          _load,
                        );
                      },
                      decoration: const InputDecoration(
                        hintText: 'Search Tag No, item or supplier',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error ??
                                (_search.text.isEmpty
                                    ? '$_total items on the shop PC'
                                    : '$_total found'),
                            key: const Key('stockItemCount'),
                            style: TextStyle(
                              color: _error == null
                                  ? AppColors.muted
                                  : AppColors.error,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          key: const Key('importStockExport'),
                          onPressed: _loading ? null : _import,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Import Excel'),
                        ),
                      ],
                    ),
                    if (_loading) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    for (final it in _items)
                      Card(
                        child: ListTile(
                          key: Key('stockItem_${it['tag_no']}'),
                          onTap: () => _details(it),
                          title: Text(
                            '${it['tag_no']}  ·  ${it['item_name'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              'Gr ${(it['gross_wt'] as num? ?? 0).toStringAsFixed(3)} g',
                              'Net ${(it['net_wt'] as num? ?? 0).toStringAsFixed(3)} g',
                              if ((it['supplier_name'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                '${it['supplier_name']}',
                            ].join(' · '),
                          ),
                          trailing: (it['mrp'] as num? ?? 0) == 0
                              ? null
                              : Text(
                                  formatInr(
                                    (it['mrp'] as num).toDouble(),
                                  ).replaceAll(RegExp(r'\.00$'), ''),
                                ),
                        ),
                      ),
                    if (_items.length == 50)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Showing the first 50 — type more of the Tag No to narrow.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
