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

/// Customer details and payment mode for a bill, numbered DJB-0001…
class Bill {
  const Bill({
    required this.billNo,
    required this.customerName,
    this.phone = '',
    this.address = '',
    this.payment = PaymentMode.cash,
    required this.createdAt,
  });

  final String billNo;
  final String customerName;
  final String phone;
  final String address;
  final PaymentMode payment;
  final DateTime createdAt;

  Bill copyWith({
    String? customerName,
    String? phone,
    String? address,
    PaymentMode? payment,
  }) => Bill(
    billNo: billNo,
    customerName: customerName ?? this.customerName,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    payment: payment ?? this.payment,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'billNo': billNo,
    'customerName': customerName,
    'phone': phone,
    'address': address,
    'payment': payment.name,
    'createdAt': createdAt.toIso8601String(),
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
  );
}

/// WhatsApp numbers bills are sent to (country code, no '+').
const billWhatsAppNumbers = ['919717593594', '919667725005'];

/// "+91 97175 93594" for display.
String displayPhone(String n) => n.length == 12 && n.startsWith('91')
    ? '+91 ${n.substring(2, 7)} ${n.substring(7)}'
    : '+$n';

/// One line of the cost break-up.
class BillLine {
  const BillLine(this.label, this.paise, {this.detail, this.bold = false});
  final String label;
  final int paise;
  final String? detail;
  final bool bold;
}

/// Item description, e.g. "18K gold · 5.886 g · DIA 0.38 ct".
List<(String, String)> billItemRows(JewelleryInput i, PricingResult r) => [
  if ((i.tagNumber ?? '').isNotEmpty) ('Tag No.', i.tagNumber!),
  ('Gold purity', r.purity.label),
  ('Gold weight', '${i.goldWeight!.toStringAsFixed(3)} g'),
  if (i.grossWeight != null)
    ('Gross weight', '${i.grossWeight!.toStringAsFixed(3)} g'),
];

/// The full cost break-up, as on the cost summary (zero lines left out).
List<BillLine> billLines(JewelleryInput i, PricingResult r) {
  final lines = <BillLine>[
    BillLine(
      'Gold value',
      r.goldValuePaise,
      detail:
          '${i.goldWeight!.toStringAsFixed(3)} g × ${formatInr(r.goldRatePerGram)}/g',
    ),
  ];
  for (var k = 0; k < i.stones.length; k++) {
    final s = i.stones[k];
    if (!s.hasWeight || i.isExcluded(s.kind)) continue;
    final v = k < r.stoneLinePaise.length ? r.stoneLinePaise[k] : 0;
    if (v <= 0) continue;
    lines.add(
      BillLine(
        '${s.kind.label} — ${s.displayName}',
        v,
        detail: s.isPieces
            ? '${formatPercent(s.weightCt!)} pcs × ${formatInr(s.ratePerCt!)}'
                  '${s.effectiveFactor == 1 ? '' : ' × ${s.effectiveFactor}'}'
            : '${s.weightCt!.toStringAsFixed(2)} ct × ${formatInr(s.ratePerCt!)}/ct',
      ),
    );
  }
  if (r.wastagePaise > 0) lines.add(BillLine('Wastage', r.wastagePaise));
  lines.add(
    BillLine(
      'Making / labour',
      r.makingPaise,
      detail: switch (i.makingMethod) {
        MakingMethod.perGram =>
          '${formatInr(i.makingValue!)}/g × ${i.goldWeight!.toStringAsFixed(3)} g',
        MakingMethod.fixed => 'Fixed amount',
        MakingMethod.percentOfGold =>
          '${formatPercent(i.makingValue!)}% of gold value',
      },
    ),
  );
  lines.add(BillLine('Subtotal', r.subtotalPaise, bold: true));
  for (final g in r.gstLines) {
    lines.add(
      BillLine(
        '${g.label} @ ${formatPercent(g.ratePercent)}%',
        g.amountPaise,
        detail: 'on ${formatPaise(g.basePaise)}',
      ),
    );
  }
  return lines;
}

String _date(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);

/// WhatsApp-friendly bill text (*bold* is WhatsApp markup).
String buildBillText(Bill b, JewelleryInput i, PricingResult r) {
  final s = StringBuffer()
    ..writeln('*${Brand.name}*')
    ..writeln('*Bill ${b.billNo}* — ${_date(b.createdAt)}')
    ..writeln()
    ..writeln('Customer: ${b.customerName}');
  if (b.phone.isNotEmpty) s.writeln('Phone: ${b.phone}');
  if (b.address.isNotEmpty) s.writeln('Address: ${b.address}');
  s.writeln();
  for (final (k, v) in billItemRows(i, r)) {
    s.writeln('$k: $v');
  }
  s.writeln();
  for (final l in billLines(i, r)) {
    final line =
        '${l.label}${l.detail == null ? '' : ' (${l.detail})'}: ${formatPaise(l.paise)}';
    s.writeln(l.bold ? '*$line*' : line);
  }
  s
    ..writeln()
    ..writeln('*TOTAL: ${formatPaise(r.totalPaise)}*')
    ..write('Payment: ${b.payment.label}');
  return s.toString();
}

/// Printable A4 bill. Uses the bundled Inter font (it has the ₹ sign).
Future<Uint8List> buildBillPdf(
  Bill b,
  JewelleryInput i,
  PricingResult r,
) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter_400Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter_600SemiBold.ttf'),
  );
  const gold = PdfColor.fromInt(0xFF8A6524);
  const soft = PdfColor.fromInt(0xFFF6EEDF);
  const muted = PdfColor.fromInt(0xFF8A7A63);
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
          width: 80,
          child: pw.Text(k, style: const pw.TextStyle(color: muted)),
        ),
        pw.Expanded(child: pw.Text(v)),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
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
          if (b.phone.isNotEmpty) kv('Phone', b.phone),
          if (b.address.isNotEmpty) kv('Address', b.address),
          pw.SizedBox(height: 12),
          pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final (k, v) in billItemRows(i, r)) kv(k, v),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(
              color: const PdfColor.fromInt(0xFFDCCFB5),
              width: 0.5,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: soft),
                children: [
                  _cell('Description', bold: true),
                  _cell('Amount', bold: true, right: true),
                ],
              ),
              for (final l in billLines(i, r))
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            l.label,
                            style: pw.TextStyle(
                              fontWeight: l.bold
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                          if (l.detail != null)
                            pw.Text(
                              l.detail!,
                              style: const pw.TextStyle(
                                fontSize: 8.5,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _cell(formatPaise(l.paise), bold: l.bold, right: true),
                  ],
                ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: soft),
                children: [
                  _cell('TOTAL', bold: true, size: 13),
                  _cell(
                    formatPaise(r.totalPaise),
                    bold: true,
                    right: true,
                    size: 13,
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Payment mode: ${b.payment.label}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Spacer(),
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
          pw.Text(
            'Thank you for shopping with us.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(color: muted, fontSize: 9),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _cell(
  String t, {
  bool bold = false,
  bool right = false,
  double size = 10,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  child: pw.Text(
    t,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);
