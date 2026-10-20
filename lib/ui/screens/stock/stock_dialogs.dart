import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_state.dart';
import '../../../stock/stock_book.dart';
import '../../../stock/stock_models.dart';
import '../../../stock/stock_sync.dart';
import '../../theme.dart';

// Dialog text controllers are left to the garbage collector: disposing them
// as the dialog pops breaks its closing animation.

TextField _pinField(TextEditingController c, String label, Key key) =>
    TextField(
      key: key,
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      decoration: InputDecoration(labelText: label),
    );

/// Who approves: picked from the shop PC's staff list when there is one
/// (so the database gets the exact name), else typed.
/// The person who counted ([exclude]) is left out: they cannot approve.
Widget _managerField(
  BuildContext context,
  TextEditingController name, {
  String? exclude,
}) {
  final staff = AppScope.read(context).stockSync.staff;
  if (staff.isEmpty) {
    return TextField(
      key: const Key('managerName'),
      controller: name,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Approved by (name)'),
    );
  }
  final ex = exclude?.trim().toLowerCase() ?? '';
  final names = [
    for (final s in staff)
      if (s.name.trim().toLowerCase() != ex) s.name,
  ];
  return DropdownButtonFormField<String>(
    key: const Key('managerName'),
    initialValue: names.contains(name.text) ? name.text : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Approved by'),
    items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
    onChanged: (v) => name.text = v ?? '',
  );
}

Widget _error(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          error,
          key: const Key('pinError'),
          style: const TextStyle(color: AppColors.error),
        ),
      );

/// "My PIN": a staff member creates their own PIN, or changes it.
Future<void> showMyPinDialog(BuildContext context, StockBook book) async {
  final staff = AppScope.read(context).stockSync.staff;
  final name = TextEditingController(
    text: staff.length == 1 ? staff.first.name : '',
  );
  final current = TextEditingController();
  final pin = TextEditingController();
  final again = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        final has = name.text.trim().isNotEmpty && book.pins.hasPin(name.text);
        return AlertDialog(
          title: Text(has ? 'Change my PIN' : 'Create my PIN'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Everyone has their own PIN: to start a stock count and '
                    'to approve someone else\'s.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  if (staff.isEmpty)
                    TextField(
                      key: const Key('myPinName'),
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      onChanged: (_) => setLocal(() {}),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('myPinName'),
                      initialValue: name.text.isEmpty ? null : name.text,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      items: [
                        for (final s in staff)
                          DropdownMenuItem(
                            value: s.name,
                            child: Text(
                              '${s.name}${book.pins.hasPin(s.name) ? '' : ' (no PIN yet)'}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => name.text = v ?? ''),
                    ),
                  if (has)
                    _pinField(current, 'Current PIN', const Key('pinCurrent')),
                  _pinField(pin, 'New PIN (4–8 digits)', const Key('pinNew')),
                  _pinField(again, 'Repeat new PIN', const Key('pinAgain')),
                  _error(error),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('pinSave'),
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  setLocal(() => error = 'Choose your name');
                  return;
                }
                if (pin.text != again.text) {
                  setLocal(() => error = 'The two PINs do not match');
                  return;
                }
                try {
                  await book.pins.setPin(
                    name.text,
                    pin.text,
                    currentPin: current.text,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } on StockException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('PIN saved for ${name.text}')));
  }
}

/// The counter signs in: enters their PIN, or creates it the first time.
/// Returns the PIN once it is accepted (null when cancelled).
Future<String?> showPinEntry(
  BuildContext context,
  StockBook book,
  String name,
) async {
  final creating = !book.pins.hasPin(name);
  final pin = TextEditingController();
  final again = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(creating ? 'Create your PIN, $name' : 'PIN for $name'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                creating
                    ? 'First time: choose a 4–8 digit PIN. You will enter it '
                          'each time you start a stock count.'
                    : 'Enter your PIN to start counting.',
                style: const TextStyle(color: AppColors.muted),
              ),
              _pinField(
                pin,
                creating ? 'New PIN (4–8 digits)' : 'Your PIN',
                const Key('userPin'),
              ),
              if (creating)
                _pinField(again, 'Repeat new PIN', const Key('userPinAgain')),
              _error(error),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('userPinOk'),
            onPressed: () async {
              if (creating && pin.text != again.text) {
                setLocal(() => error = 'The two PINs do not match');
                return;
              }
              try {
                creating
                    ? await book.pins.setPin(name, pin.text)
                    : await book.pins.verify(name, pin.text);
                if (context.mounted) Navigator.pop(context, pin.text);
              } on StockException catch (e) {
                setLocal(() => error = e.message);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

/// Asks a manager to authorise an action. [run] performs it and may throw
/// [StockException], shown in the dialog. Returns true when it succeeded.
Future<bool> showManagerDialog(
  BuildContext context,
  StockBook book, {
  required String title,
  required String message,
  bool needReason = false,
  String? counter,
  required Future<void> Function(String manager, String pin, String reason) run,
}) async {
  final name = TextEditingController();
  final pin = TextEditingController();
  final reason = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, style: const TextStyle(color: AppColors.muted)),
              _managerField(context, name, exclude: counter),
              _pinField(pin, 'Approver PIN', const Key('managerPinField')),
              if (needReason)
                TextField(
                  key: const Key('managerReason'),
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('managerConfirm'),
            onPressed: () async {
              try {
                await run(name.text, pin.text, reason.text);
                if (context.mounted) Navigator.pop(context, true);
              } on StockException catch (e) {
                setLocal(() => error = e.message);
              }
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// Free-text remark for one item (or the whole day).
Future<String?> showRemarkDialog(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  final c = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('remarkField'),
        controller: c,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          hintText: 'e.g. 1 piece sent for repair',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('remarkSave'),
          onPressed: () => Navigator.pop(context, c.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Manager-approved change to expected stock (received, sold, transferred).
Future<bool> showAdjustmentDialog(
  BuildContext context,
  StockBook book, {
  String? counter,
  required Future<void> Function(
    String code,
    int qty,
    String reason,
    String manager,
    String pin,
  )
  run,
}) async {
  var code = stockItems.first.code;
  var sign = 1;
  final qty = TextEditingController();
  final reason = TextEditingController();
  final name = TextEditingController();
  final pin = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Stock adjustment'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Changes today\'s expected stock (e.g. items received or '
                  'sold). Earlier closing balances are never changed. '
                  'Needs manager approval.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('adjItem'),
                  initialValue: code,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final i in stockItems)
                      DropdownMenuItem(
                        value: i.code,
                        child: Text(
                          '${i.label} (${i.name})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => code = v ?? code),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  key: const Key('adjSign'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Add (+)')),
                    ButtonSegment(value: -1, label: Text('Remove (−)')),
                  ],
                  selected: {sign},
                  onSelectionChanged: (s) => setLocal(() => sign = s.first),
                ),
                TextField(
                  key: const Key('adjQty'),
                  controller: qty,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Quantity (pcs)',
                  ),
                ),
                TextField(
                  key: const Key('adjReason'),
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'e.g. 2 received from workshop',
                  ),
                ),
                _managerField(context, name, exclude: counter),
                _pinField(pin, 'Approver PIN', const Key('managerPinField')),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('managerConfirm'),
            onPressed: () async {
              final n = int.tryParse(qty.text) ?? 0;
              try {
                await run(code, sign * n, reason.text, name.text, pin.text);
                if (context.mounted) Navigator.pop(context, true);
              } on StockException catch (e) {
                setLocal(() => error = e.message);
              }
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// Sets the shop PC address (PocketBase), with a connection test.
Future<void> showServerDialog(BuildContext context, StockSync sync) async {
  final url = TextEditingController(text: sync.serverUrl);
  String? message;
  var ok = false;
  var testing = false;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        Future<void> test() async {
          final u = StockSync.normalise(url.text);
          if (u.isEmpty) {
            setLocal(() {
              ok = false;
              message = 'Enter the PC address, e.g. 192.168.1.10:8090';
            });
            return;
          }
          setLocal(() => testing = true);
          final err = await sync.test(u);
          setLocal(() {
            testing = false;
            ok = err == null;
            message = err ?? 'Connected to $u';
          });
        }

        return AlertDialog(
          title: const Text('Shop PC (database)'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Stock counts are saved on this phone and shared through '
                  'PocketBase on the shop PC. Enter the PC address shown by '
                  'ipconfig, with port 8090.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('serverUrl'),
                  controller: url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'PC address',
                    hintText: '192.168.1.10:8090',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                if (testing)
                  const LinearProgressIndicator()
                else if (message != null)
                  Text(
                    message!,
                    key: const Key('serverMessage'),
                    style: TextStyle(
                      color: ok ? AppColors.ok : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('serverTest'),
              onPressed: testing ? null : test,
              child: const Text('Test'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('serverSave'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  if (save == true) await sync.setServerUrl(url.text);
}
