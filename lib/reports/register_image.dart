import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../branding.dart';
import '../ui/theme.dart';
import 'sales_register.dart';

/// Draws the day's register as a clean table image (PNG), like a printed
/// "CUSTOMER REGISTER" sheet: No. / R-N, Name, Mobile, Item.
Future<Uint8List> renderRegisterPng(
  SalesRegister r, {
  double width = 1600,
}) async {
  const margin = 30.0, rowH = 50.0, pad = 12.0;
  const columns = [
    'No. / R-N',
    'Name',
    'Mobile',
    'Metal',
    'Item',
    'Sale / Exch.',
  ];
  const fractions = [0.11, 0.25, 0.17, 0.12, 0.20, 0.15];
  const ink = Color(0xFF1F1F1F);
  const line = Color(0xFF2B2B2B);

  final tableW = width - margin * 2;
  final colW = [for (final f in fractions) tableW * f];
  final rows = r.entries.isEmpty ? [const SalesEntry(no: 0)] : r.entries;
  const titleH = 118.0;
  final height = titleH + rowH * (rows.length + 1) + margin + 70;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFFFFFFFF),
  );

  void text(
    String s,
    Offset at, {
    double size = 24,
    bool bold = false,
    double? maxWidth,
    bool centre = false,
    Color color = ink,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: appFont,
          fontSize: size,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? width);
    final dx = centre ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  text(
    'CUSTOMER REGISTER',
    Offset(width / 2, 38),
    size: 34,
    bold: true,
    centre: true,
  );
  text(
    '${Brand.name}  ·  Today\'s sales  ·  ${r.dateLabel}',
    Offset(width / 2, 80),
    size: 22,
    centre: true,
    color: const Color(0xFF6B5B45),
  );

  final top = titleH;
  final border = Paint()
    ..color = line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final shade = Paint()..color = const Color(0xFFF7F3EA);

  for (var i = 0; i <= rows.length; i++) {
    final y = top + i * rowH;
    if (i > 0 && i.isEven) {
      canvas.drawRect(Rect.fromLTWH(margin, y, tableW, rowH), shade);
    }
    var x = margin;
    for (var c = 0; c < columns.length; c++) {
      final cell = i == 0
          ? columns[c]
          : r.entries.isEmpty
          ? ''
          : switch (c) {
              0 => rows[i - 1].numberLabel,
              1 => rows[i - 1].name,
              2 => rows[i - 1].mobile.isEmpty ? '—' : rows[i - 1].mobile,
              3 => rows[i - 1].metal.label,
              4 => rows[i - 1].item.isEmpty ? '—' : rows[i - 1].item,
              _ => rows[i - 1].deal.label,
            };
      text(
        cell,
        Offset(x + pad, y + rowH / 2),
        bold: i == 0,
        maxWidth: colW[c] - pad * 2,
      );
      x += colW[c];
    }
  }
  // Grid: outer box, header rule, row rules and column rules.
  final tableH = rowH * (rows.length + 1);
  canvas.drawRect(Rect.fromLTWH(margin, top, tableW, tableH), border);
  for (var i = 1; i <= rows.length; i++) {
    final y = top + i * rowH;
    canvas.drawLine(
      Offset(margin, y),
      Offset(margin + tableW, y),
      border..strokeWidth = i == 1 ? 3 : 1.5,
    );
  }
  var x = margin;
  for (var c = 0; c < columns.length - 1; c++) {
    x += colW[c];
    canvas.drawLine(
      Offset(x, top),
      Offset(x, top + tableH),
      border..strokeWidth = 2,
    );
  }

  // Totals: sales/exchanges, by metal, new/repeat customers.
  int count(bool Function(SalesEntry) f) => r.entries.where(f).length;
  final totals = [
    for (final d in Deal.values) '${d.label} ${count((e) => e.deal == d)}',
    for (final m in Metal.values) '${m.label} ${count((e) => e.metal == m)}',
    for (final t in CustomerType.values)
      '${t.label} ${count((e) => e.type == t)}',
  ].join('   ·   ');
  text(
    'Total ${r.entries.length}   ·   $totals',
    Offset(margin, top + tableH + 40),
    size: 21,
    color: const Color(0xFF6B5B45),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.round(), height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
