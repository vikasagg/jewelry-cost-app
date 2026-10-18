import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_state.dart';
import '../../../stock/stock_book.dart';
import '../../../stock/stock_models.dart';
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
  late final _employee = TextEditingController(text: _day.employee);
  late final _note = TextEditingController(text: _day.note);
  final _employeeFocus = FocusNode();
  final _noteFocus = FocusNode();

  StockBook get _book => AppScope.read(context).stock;
  bool get _editable => _day.status == StockStatus.draft;

  @override
  void initState() {
    super.initState();
    _employeeFocus.addListener(() {
      if (!_employeeFocus.hasFocus) _saveEmployee();
    });
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) _saveNote();
    });
  }

  @override
  void dispose() {
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

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveEmployee() async {
    if (_editable && _employee.text.trim() != _day.employee) {
      await _do(() => _book.setEmployee(_day, _employee.text));
    }
  }

  Future<void> _saveNote() async {
    if (_editable && _note.text.trim() != _day.note) {
      await _do(() => _book.setNote(_day, _note.text));
    }
  }

  Future<void> _enterCount(StockItem item) async {
    if (!_editable) return;
    final v = await showNumericKeypad(
      context,
      title: item.group == item.name
          ? item.name
          : '${item.group} – ${item.code}',
      subtitle: '${item.name} · expected ${_day.expected(item.code)} pcs',
      initial: _day.count(item.code),
    );
    if (v != null) await _do(() => _book.setCount(_day, item.code, v));
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
        'Differences stay recorded.',
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
                    child: Text(
                      stockDateLabel(d.date),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusChip(status: d.status),
                ],
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
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Employee name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
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
        _Head('Prev'),
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
    required this.onCount,
    required this.onRemark,
  });
  final StockItem item;
  final DailyStock day;
  final bool grouped;
  final bool editable;
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
              _Num('${day.previousClosing(item.code)}'),
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
