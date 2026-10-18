import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../branding.dart';
import 'stock_book.dart';
import 'stock_models.dart';

String _signed(int n) => n > 0 ? '+$n' : '$n';

String stockDateLabel(String date) =>
    DateFormat('d MMM yyyy (EEE)').format(StockBook.parseDate(date));

/// "Shortage of 2", "Excess of 1" or "No difference".
String differenceLabel(int diff) => diff < 0
    ? 'Shortage of ${-diff}'
    : diff > 0
    ? 'Excess of $diff'
    : 'No difference';

String approvalLabel(DailyStock d) => switch (d.status) {
  StockStatus.verified =>
    'Verified by ${d.approvedBy}'
        '${d.approvedAt == null ? '' : ' on ${DateFormat('d MMM yyyy, h:mm a').format(d.approvedAt!)}'}',
  StockStatus.submitted => 'Submitted — awaiting manager approval',
  StockStatus.draft => 'Draft — not yet submitted',
};

/// WhatsApp-friendly daily stock summary (*bold* uses WhatsApp markup).
String buildStockSummaryText(DailyStock d) {
  final b = StringBuffer()
    ..writeln('*${Brand.name}*')
    ..writeln('*Daily Stock Summary* — ${stockDateLabel(d.date)}')
    ..writeln('Employee: ${d.employee.isEmpty ? '—' : d.employee}')
    ..writeln()
    ..writeln('Category: expected / physical / difference');
  for (final g in stockGroups) {
    final items = stockItems.where((i) => i.group == g).toList();
    if (items.length > 1) {
      b.writeln(
        '*$g*: ${d.groupExpected(g)} / ${d.groupCount(g)} / '
        '${_signed(d.groupCount(g) - d.groupExpected(g))}',
      );
    }
    for (final i in items) {
      final diff = d.difference(i.code);
      final name = items.length > 1
          ? '  • ${i.code} (${i.name})'
          : '*${i.name}*';
      b.writeln(
        '$name: ${d.expected(i.code)} / ${d.count(i.code) ?? '—'} / '
        '${diff == null ? '—' : _signed(diff)}${(diff ?? 0) != 0 ? ' ⚠' : ''}',
      );
    }
  }
  b
    ..writeln()
    ..writeln('Total expected stock: ${d.totalExpected}')
    ..writeln('Total physical stock: ${d.totalCount}')
    ..writeln(
      d.hasOpening
          ? 'Overall: *${differenceLabel(d.totalDifference)}*'
          : 'Overall: first count — sets the opening stock (nothing to compare yet)',
    );
  final remarks = [
    for (final i in stockItems)
      if ((d.remarks[i.code] ?? '').isNotEmpty)
        '• ${i.code}: ${d.remarks[i.code]}',
    if (d.note.isNotEmpty) '• ${d.note}',
  ];
  if (remarks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Remarks:')
      ..writeAll(remarks, '\n')
      ..writeln();
  }
  if (d.adjustments.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Approved adjustments:');
    for (final a in d.adjustments) {
      b.writeln(
        '• ${a.code} ${_signed(a.qty)} — ${a.reason} (${a.approvedBy})',
      );
    }
  }
  b
    ..writeln()
    ..write('Status: ${approvalLabel(d)}');
  return b.toString();
}

/// One-page PDF of the daily stock summary.
Future<Uint8List> buildStockSummaryPdf(DailyStock d) async {
  const gold = PdfColor.fromInt(0xFF8A6A2B);
  const soft = PdfColor.fromInt(0xFFF6EEDC);
  const warn = PdfColor.fromInt(0xFFB3261E);
  final doc = pw.Document(title: 'Daily Stock Summary ${d.date}');

  pw.Widget cell(
    String t, {
    bool bold = false,
    PdfColor? color,
    bool right = true,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(
      t,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: soft),
      children: [
        cell('Category', bold: true, right: false),
        cell('Prev. closing', bold: true),
        cell('Expected', bold: true),
        cell('Physical', bold: true),
        cell('Difference', bold: true),
        cell('Remark', bold: true, right: false),
      ],
    ),
  ];
  for (final g in stockGroups) {
    final items = stockItems.where((i) => i.group == g).toList();
    for (final i in items) {
      final diff = d.difference(i.code);
      rows.add(
        pw.TableRow(
          children: [
            cell(
              items.length > 1 ? '$g – ${i.code} (${i.name})' : i.name,
              right: false,
            ),
            cell('${d.previousClosing(i.code)}'),
            cell('${d.expected(i.code)}'),
            cell('${d.count(i.code) ?? '—'}'),
            cell(
              diff == null ? '—' : _signed(diff),
              bold: (diff ?? 0) != 0,
              color: (diff ?? 0) != 0 ? warn : null,
            ),
            cell(d.remarks[i.code] ?? '', right: false),
          ],
        ),
      );
    }
    if (items.length > 1) {
      final diff = d.groupCount(g) - d.groupExpected(g);
      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            cell('$g total', bold: true, right: false),
            cell(''),
            cell('${d.groupExpected(g)}', bold: true),
            cell('${d.groupCount(g)}', bold: true),
            cell(_signed(diff), bold: true, color: diff != 0 ? warn : null),
            cell(''),
          ],
        ),
      );
    }
  }
  rows.add(
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: soft),
      children: [
        cell('Grand total', bold: true, right: false),
        cell(''),
        cell('${d.totalExpected}', bold: true),
        cell('${d.totalCount}', bold: true),
        cell(
          _signed(d.totalDifference),
          bold: true,
          color: d.totalDifference != 0 ? warn : null,
        ),
        cell(''),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          Brand.name,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: gold,
          ),
        ),
        pw.Text(
          'Daily Stock Summary — ${stockDateLabel(d.date)}',
          style: const pw.TextStyle(fontSize: 13),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Employee: ${d.employee.isEmpty ? '—' : d.employee}'),
        pw.Text(
          d.hasOpening
              ? 'Expected opening = verified closing of ${stockDateLabel(d.openingFrom!)}'
              : 'First count — no previous verified closing stock',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.3),
            5: pw.FlexColumnWidth(3),
          },
          children: rows,
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Overall: ${differenceLabel(d.totalDifference)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        if (d.note.isNotEmpty) pw.Text('Remark: ${d.note}'),
        if (d.adjustments.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Approved adjustments',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          for (final a in d.adjustments)
            pw.Text(
              '• ${a.code} ${_signed(a.qty)} — ${a.reason} (approved by ${a.approvedBy})',
            ),
        ],
        pw.SizedBox(height: 8),
        pw.Text(
          'Status: ${approvalLabel(d)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Physical stock count only — no prices or gold rates are included or changed.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}
