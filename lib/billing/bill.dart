import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../branding.dart';
import '../core/money.dart';
import '../models/jewellery_input.dart';
import '../pricing/pricing_engine.dart';

enum PaymentMode {
  cash('Cash'),
  upi('UPI'),
  card('Card');

  const PaymentMode(this.label);
  final String label;
}

/// One product on a bill: a snapshot of a saved estimate, so later edits
/// to the estimate never change a bill already given to the customer.
class BillItem {
  const BillItem({
    required this.recordId,
    required this.input,
    required this.result,
  });

  final String recordId;
  final JewelleryInput input;
  final PricingResult result;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'input': input.toJson(),
    'result': result.toJson(),
  };

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
    recordId: j['recordId'] as String,
    input: JewelleryInput.fromJson((j['input'] as Map).cast<String, dynamic>()),
    result: PricingResult.fromJson(
      (j['result'] as Map).cast<String, dynamic>(),
    ),
  );
}

/// A bill for one or more products, numbered DJB-0001…, with the
/// customer's details and payment mode.
class Bill {
  const Bill({
    required this.billNo,
    required this.customerName,
    this.phone = '',
    this.address = '',
    this.payment = PaymentMode.cash,
    required this.createdAt,
    this.items = const [],
  });

  final String billNo;
  final String customerName;
  final String phone;
  final String address;
  final PaymentMode payment;
  final DateTime createdAt;
  final List<BillItem> items;

  int get subtotalPaise => items.fold(0, (a, i) => a + i.result.subtotalPaise);
  int get gstPaise => items.fold(0, (a, i) => a + i.result.gstPaise);
  int get totalPaise => items.fold(0, (a, i) => a + i.result.totalPaise);

  /// GST added up across products by label and rate, e.g. "GST @ 3%".
  List<(String, int)> get gstSummary {
    final out = <String, int>{};
    for (final i in items) {
      for (final g in i.result.gstLines) {
        final k = '${g.label} @ ${formatPercent(g.ratePercent)}%';
        out[k] = (out[k] ?? 0) + g.amountPaise;
      }
    }
    return [for (final e in out.entries) (e.key, e.value)];
  }

  Bill copyWith({
    String? customerName,
    String? phone,
    String? address,
    PaymentMode? payment,
    List<BillItem>? items,
  }) => Bill(
    billNo: billNo,
    customerName: customerName ?? this.customerName,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    payment: payment ?? this.payment,
    createdAt: createdAt,
    items: items ?? this.items,
  );

  Map<String, dynamic> toJson() => {
    'billNo': billNo,
    'customerName': customerName,
    'phone': phone,
    'address': address,
    'payment': payment.name,
    'createdAt': createdAt.toIso8601String(),
    'items': [for (final i in items) i.toJson()],
  };

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
    billNo: j['billNo'] as String,
    customerName: j['customerName'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    address: j['address'] as String? ?? '',
    payment: PaymentMode.values.firstWhere(
      (p) => p.name == j['payment'],
      orElse: () => PaymentMode.cash,
    ),
    createdAt: DateTime.parse(j['createdAt'] as String),
    items: [
      for (final i in (j['items'] as List? ?? const []))
        BillItem.fromJson((i as Map).cast<String, dynamic>()),
    ],
  );
}

/// WhatsApp numbers bills are sent to (country code, no '+').
const billWhatsAppNumbers = ['919717593594', '919667725005'];

/// "+91 97175 93594" for display.
String displayPhone(String n) => n.length == 12 && n.startsWith('91')
    ? '+91 ${n.substring(2, 7)} ${n.substring(7)}'
    : '+$n';

/// Column headings of the product table, matching [BillRow.cells].
const billColumns = [
  '#',
  'Item',
  'Purity',
  'Net wt (g)',
  'Rate / g',
  'Gold',
  'Diamond / stone',
  'Making',
  'GST',
  'Amount',
];

/// One product's row in the bill table.
class BillRow {
  BillRow(this.no, BillItem item) : i = item.input, r = item.result;
  final int no;
  final JewelleryInput i;
  final PricingResult r;

  String get title {
    final t = [
      i.tagNumber,
      i.itemName,
    ].where((s) => (s ?? '').trim().isNotEmpty).join(' · ');
    return t.isEmpty ? 'Item $no' : t;
  }

  /// Small print under the item name: gross weight, each stone line,
  /// wastage and how making was charged.
  List<String> get details => [
    if (i.grossWeight != null) 'Gross ${i.grossWeight!.toStringAsFixed(3)} g',
    for (var k = 0; k < i.stones.length; k++)
      if (i.stones[k].hasWeight &&
          !i.isExcluded(i.stones[k].kind) &&
          k < r.stoneLinePaise.length &&
          r.stoneLinePaise[k] > 0)
        _stoneDetail(i.stones[k], r.stoneLinePaise[k]),
    if (r.wastagePaise > 0) 'Wastage ${formatPaise(r.wastagePaise)}',
    'Making ${switch (i.makingMethod) {
      MakingMethod.perGram => '${formatInr(i.makingValue!)}/g',
      MakingMethod.fixed => 'fixed',
      MakingMethod.percentOfGold => '${formatPercent(i.makingValue!)}% of gold',
    }}',
  ];

  static String _stoneDetail(StoneLine s, int paise) => s.isPieces
      ? '${s.displayName} ${formatPercent(s.weightCt!)} pcs × '
            '${formatInr(s.ratePerCt!)} = ${formatPaise(paise)}'
      : '${s.displayName} ${s.weightCt!.toStringAsFixed(2)} ct × '
            '${formatInr(s.ratePerCt!)}/ct = ${formatPaise(paise)}';

  int get stonesPaise =>
      r.diamondValuePaise + r.stoneValuePaise + r.polkiValuePaise;

  /// Making includes wastage (shown in [details]).
  int get makingPaise => r.makingPaise + r.wastagePaise;

  List<String> get cells => [
    '$no',
    title,
    r.purity.label,
    i.goldWeight!.toStringAsFixed(3),
    formatInr(r.goldRatePerGram),
    formatPaise(r.goldValuePaise),
    stonesPaise == 0 ? '—' : formatPaise(stonesPaise),
    formatPaise(makingPaise),
    formatPaise(r.gstPaise),
    formatPaise(r.totalPaise),
  ];
}

List<BillRow> billRows(Bill b) => [
  for (var k = 0; k < b.items.length; k++) BillRow(k + 1, b.items[k]),
];

String _date(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);

/// Caption sent with the PDF, e.g. "Damiyaas Jewelers — Bill DJB-0001 ·
/// Asha · 2 items · ₹1,23,456.00".
String billCaption(Bill b) =>
    '${Brand.name} — Bill ${b.billNo} · ${b.customerName} · '
    '${b.items.length} item${b.items.length == 1 ? '' : 's'} · '
    '${formatPaise(b.totalPaise)}';

/// Printable A4 bill with a product table. Uses the bundled Inter font
/// (it has the ₹ sign).
Future<Uint8List> buildBillPdf(Bill b) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter_400Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter_600SemiBold.ttf'),
  );
  const gold = PdfColor.fromInt(0xFF8A6524);
  const soft = PdfColor.fromInt(0xFFF6EEDF);
  const muted = PdfColor.fromInt(0xFF8A7A63);
  const border = PdfColor.fromInt(0xFFDCCFB5);
  final doc = pw.Document(
    title: 'Bill ${b.billNo}',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  pw.Widget kv(String k, String v) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 70,
          child: pw.Text(k, style: const pw.TextStyle(color: muted)),
        ),
        pw.Expanded(child: pw.Text(v)),
      ],
    ),
  );

  pw.Widget total(String k, String v, {bool big = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            k,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: big ? 13 : 10,
              fontWeight: big ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.SizedBox(
          width: 110,
          child: pw.Text(
            v,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: big ? 13 : 10,
              fontWeight: big ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );

  final rows = billRows(b);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    Brand.name,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: gold,
                    ),
                  ),
                  pw.Text(
                    'Jewellery bill',
                    style: const pw.TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'BILL ${b.billNo}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(_date(b.createdAt)),
              ],
            ),
          ],
        ),
        pw.Divider(color: gold, thickness: 1.2),
        pw.Text(
          'Customer',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        kv('Name', b.customerName),
        if (b.phone.isNotEmpty) kv('Phone', '+91 ${b.phone}'),
        if (b.address.isNotEmpty) kv('Address', b.address),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: border, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(18),
            1: pw.FlexColumnWidth(3.2),
            2: pw.FlexColumnWidth(1.1),
            3: pw.FlexColumnWidth(1.3),
            4: pw.FlexColumnWidth(1.6),
            5: pw.FlexColumnWidth(1.8),
            6: pw.FlexColumnWidth(1.8),
            7: pw.FlexColumnWidth(1.7),
            8: pw.FlexColumnWidth(1.5),
            9: pw.FlexColumnWidth(1.9),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: soft),
              children: [
                for (var c = 0; c < billColumns.length; c++)
                  _cell(billColumns[c], bold: true, right: c > 2),
              ],
            ),
            for (final row in rows)
              pw.TableRow(
                children: [
                  for (var c = 0; c < row.cells.length; c++)
                    c == 1
                        ? pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  row.title,
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                for (final d in row.details)
                                  pw.Text(
                                    d,
                                    style: const pw.TextStyle(
                                      fontSize: 7,
                                      color: muted,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : _cell(row.cells[c], right: c > 2, bold: c == 9),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 8),
        total(
          'Items (${rows.length}) before GST',
          formatPaise(b.subtotalPaise),
        ),
        for (final (k, v) in b.gstSummary) total(k, formatPaise(v)),
        pw.Divider(color: border, thickness: 0.5),
        total('TOTAL', formatPaise(b.totalPaise), big: true),
        pw.SizedBox(height: 10),
        pw.Text(
          'Payment mode: ${b.payment.label}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 50),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Customer signature',
              style: const pw.TextStyle(color: muted),
            ),
            pw.Text(
              'For ${Brand.name}',
              style: const pw.TextStyle(color: muted),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'Thank you for shopping with us.',
            style: const pw.TextStyle(color: muted, fontSize: 9),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _cell(String t, {bool bold = false, bool right = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        t,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
