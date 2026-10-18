import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../billing/bill.dart';
import '../../branding.dart';
import '../../core/money.dart';
import '../../models/jewellery_input.dart';
import '../../pricing/pricing_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';

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

/// The bill: customer, item, full cost break-up and payment mode. Print
/// shares the bill as a PDF (pick WhatsApp and the chat); "Print on
/// paper" opens the printer dialog.
class BillScreen extends StatefulWidget {
  const BillScreen({
    super.key,
    required this.bill,
    required this.input,
    required this.result,
    this.onEditCustomer,
  });

  final Bill bill;
  final JewelleryInput input;
  final PricingResult result;
  final VoidCallback? onEditCustomer;

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  // Built up front: browsers (iPhone Safari) only open the share sheet
  // straight after a tap, so the PDF must be ready before it.
  late final Future<Uint8List> _pdf = buildBillPdf(
    widget.bill,
    widget.input,
    widget.result,
  );
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
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/pdf', name: _pdfName),
          ],
          text:
              '${Brand.name} — Bill ${widget.bill.billNo} · '
              '${widget.bill.customerName} · '
              '${formatPaise(widget.result.totalPaise)}',
        ),
      );
    } catch (e) {
      if (mounted) _snack('Could not share the PDF: $e');
    }
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
    final i = widget.input, r = widget.result, b = widget.bill;
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
                      const SectionTitle('Item'),
                      for (final (k, v) in billItemRows(i, r))
                        InfoRow(
                          icon: const Icon(Icons.diamond_outlined, size: 18),
                          label: k,
                          value: v,
                        ),
                      const Divider(),
                      const SectionTitle('Cost break-up'),
                      for (final l in billLines(i, r))
                        BreakdownRow(
                          label: l.label,
                          value: formatPaise(l.paise),
                          caption: l.detail,
                          bold: l.bold,
                        ),
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
                            formatPaise(r.totalPaise),
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
                'Opens the share sheet with the bill PDF: pick WhatsApp, then '
                '${billWhatsAppNumbers.map(displayPhone).join(' or ')}.',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('billPrintPaper'),
                onPressed: _printOnPaper,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print on paper'),
              ),
              if (widget.onEditCustomer != null)
                TextButton.icon(
                  onPressed: widget.onEditCustomer,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit customer details'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
