import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_state.dart';
import '../../../stock/stock_book.dart';
import '../../../stock/stock_models.dart';
import '../../../stock/stock_sync.dart';
import '../../../stock/stock_report.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/numeric_keypad.dart';
import 'stock_dialogs.dart';
import 'stock_home_screen.dart' show StatusChip;

/// Count, reconcile, approve and share one day's physical stock.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.initial});
  final DailyStock initial;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  late DailyStock _day = widget.initial;

  /// The previous count (any status), shown in the "Last day" column.
  late final DailyStock? _lastDay = AppScope.read(
    context,
  ).stock.dayBefore(_day.date);
  bool _nameError = false;
  late final _employee = TextEditingController(text: _day.employee);
  late final _note = TextEditingController(text: _day.note);
  final _employeeFocus = FocusNode();
  final _noteFocus = FocusNode();

  StockBook get _book => AppScope.read(context).stock;
  bool get _editable => _day.status == StockStatus.draft;

  /// Auto-save interval.
  static const autosaveEvery = Duration(seconds: 3);
  Timer? _autosaveTimer;
  late DateTime? _savedAt = _day.savedAt;

  /// A sum still being typed on the keypad: (item code, working).
  (String, String)? _live;

  @override
  void initState() {
    super.initState();
    _autosaveTimer = Timer.periodic(autosaveEvery, (_) => _autosave());
    _employeeFocus.addListener(() {
      if (!_employeeFocus.hasFocus) _saveEmployee();
    });
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) _saveNote();
    });
  }

  /// Saves what is on screen — typed names and any sum still on the
  /// keypad — so nothing is lost if the app closes.
  Future<void> _autosave() async {
    if (!_editable || !mounted) return;
    var draft = _day.copyWith(
      employee: _employee.text.trim(),
      note: _note.text.trim(),
    );
    final live = _live;
    if (live != null) {
      final expr = CountExpression(live.$2);
      final v = expr.value;
      if (expr.isComplete && v != null && v >= 0) {
        draft = draft.copyWith(
          counts: {...draft.counts, live.$1: v},
          entries: {...draft.entries, live.$1: live.$2},
        );
      }
    }
    final at = await _book.autosave(draft);
    if (at != null && mounted) setState(() => _savedAt = at);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _employee.dispose();
    _note.dispose();
    _employeeFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// Runs a book action, showing rule violations as a message.
  Future<void> _do(Future<DailyStock> Function() action) async {
    try {
      final next = await action();
      if (mounted) setState(() => _day = next);
    } on StockException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar() // newest message replaces the last one
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveEmployee() async {
    if (_editable && _employee.text.trim() != _day.employee) {
      await _do(() => _book.setEmployee(_day, _employee.text));
    }
  }

  List<StaffMember> get _staff => AppScope.read(context).stockSync.staff;

  /// Staff list from the shop PC.
  Future<void> _pickStaff() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Who is counting?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final s in _staff)
              ListTile(
                key: Key('staff_${s.name}'),
                leading: const Icon(Icons.person_outline),
                title: Text(s.name),
                subtitle: Text('+91 ${s.phone}'),
                selected: s.name == _employee.text.trim(),
                onTap: () => Navigator.pop(context, s.name),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _employee.text = picked;
    setState(() => _nameError = false);
    await _signIn();
  }

  /// Who signed in with their PIN on this screen.
  String? _signedIn;

  /// The counter must enter their own PIN (or create it) before counting.
  Future<bool> _signIn() async {
    final name = _employee.text.trim();
    if (name.isEmpty) return false;
    if (_signedIn?.toLowerCase() == name.toLowerCase()) return true;
    final pin = await showPinEntry(context, _book, name);
    if (pin == null || !mounted) return false;
    try {
      final next = await _book.startCount(_day, name, pin);
      if (!mounted) return false;
      setState(() {
        _day = next;
        _signedIn = name;
      });
      return true;
    } on StockException catch (e) {
      _snack(e.message);
      return false;
    }
  }

  /// Name entered and PIN checked; otherwise asks for them.
  Future<bool> _ready() async {
    if (_employee.text.trim().isEmpty) {
      setState(() => _nameError = true);
      _staff.isNotEmpty ? _pickStaff() : _employeeFocus.requestFocus();
      _snack('Enter your name first');
      return false;
    }
    return _signIn();
  }

  Future<void> _saveNote() async {
    if (_editable && _note.text.trim() != _day.note) {
      await _do(() => _book.setNote(_day, _note.text));
    }
  }

  Future<void> _enterCount(StockItem item) async {
    if (!_editable) return;
    // Name and the counter's own PIN are needed before counting.
    if (!await _ready() || !mounted) return;
    final count = _day.count(item.code);
    final r = await showCountKeypad(
      context,
      title: item.group == item.name
          ? item.name
          : '${item.group} – ${item.code}',
      subtitle: '${item.name} · expected ${_day.expected(item.code)} pcs',
      initialExpression: _day.entries[item.code] ?? count?.toString(),
      onChanged: (t) => _live = (item.code, t),
    );
    _live = null;
    if (r != null) {
      await _do(
        () =>
            _book.setCount(_day, item.code, r.value, expression: r.expression),
      );
    } else {
      await _autosave(); // cancelled: put back what was there before
    }
  }

  /// Opens the count for another date (from the date picker).
  Future<void> _pickDate() async {
    final current = StockBook.parseDate(_day.date);
    final today = StockBook.parseDate(_book.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: 'Stock count date',
    );
    if (picked == null || !mounted) return;
    final key = StockBook.dateKey(picked);
    if (key == _day.date) return;
    await _autosave();
    final day = await _book.open(key);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => StockCountScreen(initial: day)),
    );
  }

  Future<void> _editRemark(StockItem item) async {
    final t = await showRemarkDialog(
      context,
      title: 'Remark — ${item.label}',
      initial: _day.remarks[item.code],
    );
    if (t != null) await _do(() => _book.setRemark(_day, item.code, t));
  }

  Future<void> _submit() async {
    if (!await _ready()) return;
    await _saveEmployee();
    await _saveNote();
    if (!mounted) return;
    final unexplained = _day.unexplained.toList();
    if (unexplained.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Differences without a remark'),
          content: Text(
            '${unexplained.map((i) => i.code).join(', ')} '
            '${unexplained.length == 1 ? 'has' : 'have'} a difference but no '
            'remark. Submit anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Add remarks'),
            ),
            FilledButton(
              key: const Key('submitAnyway'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await _do(() => _book.submit(_day));
  }

  Future<void> _verify() => showManagerDialog(
    context,
    _book,
    title: 'Verify stock count',
    message:
        'Verified counts become tomorrow\'s expected opening stock. '
        'Differences stay recorded. The approver must be someone other '
        'than ${_day.employee.isEmpty ? 'the counter' : _day.employee}.',
    counter: _day.employee,
    run: (m, p, _) async {
      final next = await _book.verify(_day, manager: m, pin: p);
      if (mounted) setState(() => _day = next);
    },
  );

  Future<void> _reopen() => showManagerDialog(
    context,
    _book,
    title: 'Reopen verified count',
    message: 'The day goes back to draft; the reason is logged.',
    needReason: true,
    run: (m, p, r) async {
      final next = await _book.reopen(_day, manager: m, pin: p, reason: r);
      if (mounted) setState(() => _day = next);
    },
  );

  Future<void> _adjust() => showAdjustmentDialog(
    context,
    _book,
    counter: _day.employee,
    run: (code, qty, reason, m, p) async {
      final next = await _book.addAdjustment(
        _day,
        code: code,
        qty: qty,
        reason: reason,
        manager: m,
        pin: p,
      );
      if (mounted) setState(() => _day = next);
    },
  );

  Future<void> _shareWhatsApp() async {
    await _saveEmployee();
    final text = buildStockSummaryText(_day);
    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      // No WhatsApp link handler: fall back to the system share sheet.
      await SharePlus.instance.share(ShareParams(text: text));
    }
    await _do(() => _book.logShare(_day, 'WhatsApp'));
  }

  Future<void> _sharePdf() async {
    await _saveEmployee();
    try {
      final bytes = await buildStockSummaryPdf(_day);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/pdf',
              name: 'stock-summary-${_day.date}.pdf',
            ),
          ],
          text: 'Daily Stock Summary — ${stockDateLabel(_day.date)}',
        ),
      );
      await _do(() => _book.logShare(_day, 'PDF'));
    } catch (e) {
      _snack('Could not share the PDF: $e');
    }
  }

  Future<void> _shareText() async {
    await _saveEmployee();
    await SharePlus.instance.share(
      ShareParams(text: buildStockSummaryText(_day)),
    );
    await _do(() => _book.logShare(_day, 'Text'));
  }

  @override
  Widget build(BuildContext context) {
    final d = _day;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Count'),
        actions: [
          IconButton(
            key: const Key('stockPickDate'),
            tooltip: 'Change date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'Share as text',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareText,
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            key: const Key('stockList'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('stockDate'),
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event,
                              size: 20,
                              color: AppColors.goldDeep,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                stockDateLabel(d.date),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: AppColors.goldDeep,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  StatusChip(status: d.status),
                ],
              ),
              if (_editable)
                Text(
                  _savedAt == null
                      ? 'Auto-saves every ${autosaveEvery.inSeconds} seconds'
                      : 'Auto-saved ${DateFormat('d MMM yyyy, h:mm:ss a').format(_savedAt!)}',
                  key: const Key('autosaveStatus'),
                  style: const TextStyle(color: AppColors.ok, fontSize: 12),
                ),
              const SizedBox(height: 4),
              Text(
                d.hasOpening
                    ? 'Expected opening = verified closing of '
                          '${stockDateLabel(d.openingFrom!)}'
                    : 'No verified closing stock yet — once verified, this '
                          'count becomes the opening stock.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              if (d.status == StockStatus.verified)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    approvalLabel(d),
                    style: const TextStyle(
                      color: AppColors.ok,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('stockEmployee'),
                controller: _employee,
                focusNode: _employeeFocus,
                enabled: _editable,
                // With a staff list from the shop PC, pick a name.
                readOnly: _staff.isNotEmpty,
                onTap: _staff.isNotEmpty ? _pickStaff : null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Employee name *',
                  prefixIcon: const Icon(Icons.person_outline),
                  suffixIcon: _staff.isNotEmpty && _editable
                      ? const Icon(Icons.arrow_drop_down)
                      : null,
                  errorText: _nameError && _employee.text.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),
                onChanged: (t) {
                  if (_nameError && t.trim().isNotEmpty) {
                    setState(() => _nameError = false);
                  }
                },
                onSubmitted: (_) => _saveEmployee(),
              ),
              const SizedBox(height: 12),
              _TotalsCard(day: d),
              const SizedBox(height: 6),
              const _ColumnHeader(),
              for (final g in stockGroups) ..._groupRows(g),
              const SizedBox(height: 8),
              TextField(
                key: const Key('stockNote'),
                controller: _note,
                focusNode: _noteFocus,
                enabled: _editable,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Overall remark (optional)',
                  prefixIcon: Icon(Icons.notes),
                ),
                onSubmitted: (_) => _saveNote(),
              ),
              if (d.adjustments.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SectionTitle('Approved adjustments'),
                for (final a in d.adjustments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${a.code} ${a.qty > 0 ? '+' : ''}${a.qty} — ${a.reason} '
                      '(${a.approvedBy}, ${DateFormat('h:mm a').format(a.at)})',
                    ),
                  ),
              ],
              if (_editable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('addAdjustment'),
                    onPressed: _adjust,
                    icon: const Icon(Icons.tune),
                    label: const Text('Stock adjustment (manager approval)'),
                  ),
                ),
              const SizedBox(height: 8),
              ..._actions(),
              const SizedBox(height: 12),
              _AuditTrail(day: d),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _groupRows(String group) {
    final items = stockItems.where((i) => i.group == group).toList();
    final d = _day;
    return [
      if (items.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldDeep,
                  ),
                ),
              ),
              Text(
                d.hasOpening
                    ? 'Exp ${d.groupExpected(group)} · Phy ${d.groupCount(group)}'
                    : 'Total ${d.groupCount(group)}',
                key: Key('groupTotal_$group'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      for (final i in items)
        _ItemRow(
          item: i,
          day: d,
          lastDay: _lastDay?.counts[i.code],
          grouped: items.length > 1,
          editable: _editable,
          onCount: () => _enterCount(i),
          onRemark: () => _editRemark(i),
        ),
    ];
  }

  List<Widget> _actions() {
    final d = _day;
    final share = [
      FilledButton.icon(
        key: const Key('stockWhatsApp'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
        ),
        onPressed: _shareWhatsApp,
        icon: const Icon(Icons.send),
        label: const Text('Share on WhatsApp'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('stockPdf'),
        onPressed: _sharePdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Share PDF report'),
      ),
    ];
    return switch (d.status) {
      StockStatus.draft => [
        FilledButton.icon(
          key: const Key('stockSubmit'),
          onPressed: _submit,
          icon: const Icon(Icons.task_alt),
          label: const Text('Submit for approval'),
        ),
        const SizedBox(height: 8),
        ...share,
      ],
      StockStatus.submitted => [
        FilledButton.icon(
          key: const Key('stockVerify'),
          onPressed: _verify,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Verify (manager)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('stockEdit'),
          onPressed: () => _do(() => _book.editSubmitted(_day)),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit count'),
        ),
        const SizedBox(height: 8),
        ...share,
      ],
      StockStatus.verified => [
        ...share,
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('stockReopen'),
          onPressed: _reopen,
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Reopen (manager)'),
        ),
      ],
    };
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.day});
  final DailyStock day;

  @override
  Widget build(BuildContext context) {
    final diff = day.totalDifference;
    final counted = stockItems
        .where((i) => day.counts.containsKey(i.code))
        .length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Total(
                'Expected',
                '${day.totalExpected}',
                key: const Key('totalExpected'),
              ),
              _Total(
                'Physical',
                '${day.totalCount}',
                key: const Key('totalPhysical'),
              ),
              _Total(
                'Difference',
                diff > 0 ? '+$diff' : '$diff',
                color: diff == 0 ? AppColors.ok : AppColors.error,
                key: const Key('totalDifference'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${day.hasOpening ? differenceLabel(diff) : 'Opening count'} · '
            'counted $counted of ${stockItems.length} categories',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: diff == 0 ? AppColors.ok : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, {this.color, super.key});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
    child: Row(
      children: [
        Expanded(flex: 5, child: SizedBox()),
        _Head('Last day'),
        _Head('Exp'),
        _Head('Count'),
        _Head('Diff'),
      ],
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 2,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: AppColors.muted),
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.day,
    required this.grouped,
    required this.editable,
    required this.lastDay,
    required this.onCount,
    required this.onRemark,
  });
  final StockItem item;
  final DailyStock day;
  final bool grouped;
  final bool editable;

  /// The previous count of this item (null: no earlier count).
  final int? lastDay;
  final VoidCallback onCount;
  final VoidCallback onRemark;

  @override
  Widget build(BuildContext context) {
    final diff = day.difference(item.code);
    final count = day.count(item.code);
    final remark = day.remarks[item.code];
    final flagged = (diff ?? 0) != 0;
    final adj = day.adjustmentFor(item.code);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: flagged ? AppColors.warnSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: flagged
              ? AppColors.warn.withValues(alpha: 0.5)
              : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grouped ? item.code : item.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (grouped)
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              _Num('${lastDay ?? '—'}'),
              _Num(
                '${day.expected(item.code)}',
                hint: adj == 0 ? null : (adj > 0 ? '+$adj adj' : '$adj adj'),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  button: true,
                  label: 'Count ${item.code}',
                  child: InkWell(
                    key: Key('count_${item.code}'),
                    onTap: editable ? onCount : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: editable ? AppColors.goldSoft : AppColors.tile,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: count == null && editable
                              ? AppColors.gold
                              : Colors.transparent,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        count?.toString() ?? '—',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _Num(
                diff == null ? '—' : (diff > 0 ? '+$diff' : '$diff'),
                key: Key('diff_${item.code}'),
                color: diff == null || diff == 0
                    ? AppColors.ok
                    : AppColors.error,
                bold: true,
              ),
            ],
          ),
          if (day.entries[item.code] case final w?
              when CountExpression(w).hasWorking)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Text(
                '${CountExpression(w).pretty} = ${count ?? '—'}',
                key: Key('working_${item.code}'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (flagged || (remark ?? '').isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    (remark ?? '').isNotEmpty
                        ? '“$remark”'
                        : diff! < 0
                        ? 'Shortage of ${-diff} — add a remark'
                        : 'Excess of $diff — add a remark',
                    style: TextStyle(
                      fontSize: 12,
                      color: (remark ?? '').isNotEmpty
                          ? AppColors.ink
                          : AppColors.warn,
                      fontStyle: (remark ?? '').isNotEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                if (editable)
                  TextButton.icon(
                    key: Key('remark_${item.code}'),
                    onPressed: onRemark,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text((remark ?? '').isEmpty ? 'Remark' : 'Edit'),
                  ),
              ],
            )
          else if (editable && count != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('remark_${item.code}'),
                onPressed: onRemark,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('Add remark', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.text, {this.hint, this.color, this.bold = false, super.key});
  final String text;
  final String? hint;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 2,
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color ?? AppColors.ink,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
      ],
    ),
  );
}

class _AuditTrail extends StatelessWidget {
  const _AuditTrail({required this.day});
  final DailyStock day;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM, h:mm a');
    return ExpansionTile(
      key: const Key('auditTrail'),
      tilePadding: EdgeInsets.zero,
      title: Text('Audit trail (${day.audit.length})'),
      children: [
        for (final e in day.audit.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history, size: 18),
            title: Text('${e.action} — ${e.actor}'),
            subtitle: Text(
              '${fmt.format(e.at)}${e.detail == null ? '' : ' · ${e.detail}'}',
            ),
          ),
      ],
    );
  }
}
