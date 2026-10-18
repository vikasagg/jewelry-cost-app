import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../billing/bill.dart';
import '../../branding.dart';
import '../../core/money.dart';
import '../../models/calculation_record.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bill_items_screen.dart';

/// Customer details entered for a bill.
typedef BillCustomer = ({
  String name,
  String phone,
  String address,
  PaymentMode payment,
});

/// Asks for the customer's name, phone, address and payment mode (radio
/// buttons, Cash by default). Returns null when cancelled.
Future<BillCustomer?> showBillDialog(BuildContext context, {Bill? initial}) {
  // Controllers are left to the garbage collector: disposing them as the
  // dialog pops breaks its closing animation.
  final name = TextEditingController(text: initial?.customerName ?? '');
  final phone = TextEditingController(text: initial?.phone ?? '');
  final address = TextEditingController(text: initial?.address ?? '');
  var payment = initial?.payment ?? PaymentMode.cash;
  String? nameError, phoneError;
  return showDialog<BillCustomer>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Generate bill'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('billName'),
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Customer name *',
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('billPhone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    prefixText: '+91 ',
                    errorText: phoneError,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('billAddress'),
                  controller: address,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Mode of payment',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                RadioGroup<PaymentMode>(
                  groupValue: payment,
                  onChanged: (v) => setLocal(() => payment = v ?? payment),
                  child: Row(
                    children: [
                      for (final m in [
                        PaymentMode.cash,
                        PaymentMode.upi,
                        PaymentMode.card,
                      ])
                        Expanded(
                          child: InkWell(
                            onTap: () => setLocal(() => payment = m),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Radio<PaymentMode>(
                                  key: Key('pay_${m.name}'),
                                  value: m,
                                ),
                                Flexible(child: Text(m.label)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
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
            key: const Key('billOk'),
            onPressed: () {
              final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
              final local = digits.length == 12 && digits.startsWith('91')
                  ? digits.substring(2)
                  : digits;
              setLocal(() {
                nameError = name.text.trim().isEmpty
                    ? 'Enter the customer name'
                    : null;
                phoneError = local.isNotEmpty && local.length != 10
                    ? 'Enter a 10-digit mobile number'
                    : null;
              });
              if (nameError != null || phoneError != null) return;
              Navigator.pop(context, (
                name: name.text.trim(),
                phone: local,
                address: address.text.trim(),
                payment: payment,
              ));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

/// Builds a bill: pick the products (the current estimate ticked), then
/// the customer's details, then shows it. With [existing], edits that bill
/// (same number and date).
Future<void> startBill(
  BuildContext context, {
  Bill? existing,
  String? preselectId,
}) async {
  final state = AppScope.read(context);
  // A "Saved to history" message would cover the picker's Next button.
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  final picked = await Navigator.of(context).push<List<CalculationRecord>>(
    MaterialPageRoute(
      builder: (_) => BillItemsScreen(
        initialIds: existing != null
            ? [for (final i in existing.items) i.recordId]
            : [?preselectId],
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final c = await showBillDialog(context, initial: existing);
  if (c == null || !context.mounted) return;
  final bill = await state.saveBill(
    existing: existing,
    items: picked,
    customerName: c.name,
    phone: c.phone,
    address: c.address,
    payment: c.payment,
  );
  if (context.mounted) await showBill(context, bill);
}

/// Opens a saved bill; "Edit bill" goes back through [startBill].
Future<void> showBill(BuildContext context, Bill bill) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (route) => BillScreen(
          bill: bill,
          onEdit: () {
            Navigator.of(route).pop();
            startBill(context, existing: bill);
          },
        ),
      ),
    );

/// The bill: customer, a table of the products, totals and payment mode.
/// Print sends the PDF (straight to the shop's WhatsApp chats in the
/// Android app); "Print on paper" opens the printer dialog.
class BillScreen extends StatefulWidget {
  const BillScreen({super.key, required this.bill, this.onEdit});

  final Bill bill;
  final VoidCallback? onEdit;

  @override
  State<BillScreen> createState() => _BillScreenState();
}

const _whatsAppChannel = MethodChannel('damiyaas/whatsapp');

/// The Android app can hand the PDF straight to a WhatsApp chat; iPhone
/// and browsers only offer the share sheet.
bool get _directWhatsApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class _BillScreenState extends State<BillScreen> {
  // Built up front: browsers (iPhone Safari) only open the share sheet
  // straight after a tap, so the PDF must be ready before it.
  late final Future<Uint8List> _pdf = buildBillPdf(widget.bill);
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _pdf.then((b) {
      if (mounted) setState(() => _bytes = b);
    }, onError: (Object _) {});
  }

  String get _pdfName => 'bill-${widget.bill.billNo}.pdf';

  Future<void> _sendPdf() async {
    try {
      final bytes = _bytes ?? await _pdf;
      if (_directWhatsApp && await _sendToWhatsApp(bytes)) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/pdf', name: _pdfName),
          ],
          text: billCaption(widget.bill),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Could not share the PDF: $e');
    }
  }

  /// Android app: opens each shop number's WhatsApp chat in turn with the
  /// PDF attached (the next one when the user comes back). False when
  /// WhatsApp isn't installed, so the share sheet is used instead.
  Future<bool> _sendToWhatsApp(Uint8List bytes) async {
    for (final n in billWhatsAppNumbers) {
      final r = await _whatsAppChannel.invokeMethod<String>('sendFile', {
        'bytes': bytes,
        'name': _pdfName,
        'phone': n,
        'text': billCaption(widget.bill),
      });
      if (r == 'notInstalled') return false;
    }
    if (mounted) {
      _snack(
        'Bill sent to ${billWhatsAppNumbers.map(displayPhone).join(' and ')}',
      );
    }
    return true;
  }

  Future<void> _printOnPaper() async {
    try {
      await Printing.layoutPdf(name: _pdfName, onLayout: (_) => _pdf);
    } catch (e) {
      if (mounted) _snack('Could not open printing: $e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final rows = billRows(b);
    return Scaffold(
      appBar: AppBar(title: Text('Bill ${b.billNo}')),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BrandHeader(
                        subtitle:
                            'Bill ${b.billNo} · ${formatDateTime(b.createdAt)}',
                      ),
                      const Divider(),
                      const SectionTitle('Customer'),
                      InfoRow(
                        icon: const Icon(Icons.person_outline, size: 18),
                        label: 'Name',
                        value: b.customerName,
                      ),
                      if (b.phone.isNotEmpty)
                        InfoRow(
                          icon: const Icon(Icons.phone_outlined, size: 18),
                          label: 'Phone',
                          value: '+91 ${b.phone}',
                        ),
                      if (b.address.isNotEmpty)
                        InfoRow(
                          icon: const Icon(Icons.home_outlined, size: 18),
                          label: 'Address',
                          value: b.address,
                        ),
                      const Divider(),
                      SectionTitle('Products (${rows.length})'),
                      _ProductTable(rows: rows),
                      const SizedBox(height: 10),
                      _TotalRow(
                        'Products before GST',
                        formatPaise(b.subtotalPaise),
                      ),
                      for (final (k, v) in b.gstSummary)
                        _TotalRow(k, formatPaise(v)),
                      const Divider(),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            formatPaise(b.totalPaise),
                            key: const Key('billTotal'),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.goldDeep,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.goldSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Payment mode: ${b.payment.label}',
                          key: const Key('billPayment'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('billPrint'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366), // WhatsApp green
                  foregroundColor: Colors.white,
                ),
                onPressed: _sendPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _bytes == null ? 'Preparing PDF…' : 'Print — send PDF',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _directWhatsApp
                    ? 'Sends the bill PDF on WhatsApp to '
                          '${billWhatsAppNumbers.map(displayPhone).join(', then ')}'
                          ': tap Send, then Back for the next.'
                    : 'Opens the share sheet with the bill PDF: pick WhatsApp, '
                          'then ${billWhatsAppNumbers.map(displayPhone).join(' or ')}.',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('billPrintPaper'),
                onPressed: _printOnPaper,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print on paper'),
              ),
              if (widget.onEdit != null)
                TextButton.icon(
                  key: const Key('billEdit'),
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit bill (products or customer)'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The products as a table (scrolls sideways on narrow phones).
class _ProductTable extends StatelessWidget {
  const _ProductTable({required this.rows});
  final List<BillRow> rows;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
    const cell = TextStyle(fontSize: 13);
    const small = TextStyle(fontSize: 11, color: AppColors.muted);
    Widget pad(Widget w, {bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Align(
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: w,
      ),
    );
    return SingleChildScrollView(
      key: const Key('billTable'),
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        columnWidths: const {1: FixedColumnWidth(190)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(color: AppColors.line, width: 0.8),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.goldSoft),
            children: [
              for (var c = 0; c < billColumns.length; c++)
                pad(Text(billColumns[c], style: head), right: c > 2),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [
                for (var c = 0; c < r.cells.length; c++)
                  c == 1
                      ? pad(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              for (final d in r.details) Text(d, style: small),
                            ],
                          ),
                        )
                      : pad(
                          Text(
                            r.cells[c],
                            style: c == 9
                                ? cell.copyWith(fontWeight: FontWeight.w700)
                                : cell,
                          ),
                          right: c > 2,
                        ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
