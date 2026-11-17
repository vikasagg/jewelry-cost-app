import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// The rows of the first sheet of an .xlsx file: numbers as [num], text
/// as [String], empty cells as null.
List<List<Object?>> readXlsxRows(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? text(String path) {
    final f = zip.findFile(path);
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  // Shared strings: <si> holds <t> runs.
  final shared = <String>[];
  final ss = text('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final sheetPath =
      zip.files
          .map((f) => f.name)
          .where((n) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(n))
          .toList()
        ..sort();
  if (sheetPath.isEmpty) throw const FormatException('No sheet in this file');
  final sheet = XmlDocument.parse(text(sheetPath.first)!);

  int column(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch < 65 || ch > 90) break;
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  final rows = <List<Object?>>[];
  for (final row in sheet.findAllElements('row')) {
    final cells = <Object?>[];
    for (final c in row.findElements('c')) {
      final i = column(c.getAttribute('r') ?? 'A');
      while (cells.length < i) {
        cells.add(null);
      }
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText;
      Object? value;
      if (type == 's') {
        value = v == null ? null : shared[int.parse(v)];
      } else if (type == 'inlineStr') {
        value = c.findAllElements('t').map((t) => t.innerText).join();
      } else if (type == 'str' || type == 'e') {
        value = v;
      } else if (type == 'b') {
        value = v == '1';
      } else {
        value = v == null ? null : num.tryParse(v);
      }
      if (cells.length == i) {
        cells.add(value);
      } else {
        cells[i] = value;
      }
    }
    rows.add(cells);
  }
  return rows;
}

/// Export headers (letters/digits only, lower case) → stock_items fields.
/// Headers that appear twice (the diamond and stone detail blocks repeat
/// "Dia Wt" / "Stn Wt") map to the second name on their second use.
const _columns = <String, List<String>>{
  'tagno': ['tag_no'],
  'itemname': ['item_name'],
  'date': ['entry_date'],
  'pc': ['pcs'],
  'grwt': ['gross_wt'],
  'nwt': ['net_wt'],
  'diawt': ['dia_wt', 'dia_detail_wt'],
  'stnwt': ['stone_wt', 'stn_detail_wt'],
  'goldwt': ['gold_wt'],
  'design': ['design'],
  'hm': ['hallmark'],
  'certif': ['certificate'],
  'lbrgm': ['labour_per_gm'],
  'lbrrs': ['labour_rs'],
  'remarks': ['remarks'],
  'colour': ['colour'],
  'clarity': ['clarity'],
  'size': ['size'],
  'mrp': ['mrp'],
  'costing': ['costing'],
  'supplier': ['supplier_name'],
  'diaitem': ['dia_item'],
  'diaquality': ['dia_quality'],
  'diasize': ['dia_size'],
  'diapc': ['dia_pcs'],
  'rate': ['dia_rate'],
  'diavalue': ['dia_value'],
  'stnitem': ['stn_item'],
  'stnquality': ['stn_quality'],
  'stnsize': ['stn_size'],
  'stnpc': ['stn_pcs'],
  'stnrate': ['stn_rate'],
  'stnvalue': ['stn_value'],
  'goldstd': ['gold_std'],
};

/// Fields stored as numbers (the rest are text, plus a date and a flag).
const _numbers = {
  'pcs',
  'gross_wt',
  'net_wt',
  'dia_wt',
  'dia_detail_wt',
  'stone_wt',
  'stn_detail_wt',
  'gold_wt',
  'labour_per_gm',
  'labour_rs',
  'mrp',
  'costing',
  'dia_pcs',
  'dia_rate',
  'dia_value',
  'stn_pcs',
  'stn_rate',
  'stn_value',
};

/// A stock export read and ready to send to the shop PC.
class StockExport {
  StockExport(this.items, this.duplicateTags, this.skipped);

  /// One map per item, keyed by stock_items field names.
  final List<Map<String, Object?>> items;

  /// Tag numbers that appeared more than once (the last row is kept).
  final List<String> duplicateTags;

  /// Rows without a Tag No.
  final int skipped;

  Set<String> get suppliers => {
    for (final i in items)
      if ((i['supplier_name'] as String? ?? '').isNotEmpty)
        i['supplier_name']! as String,
  };

  int get withoutSupplier =>
      items.where((i) => (i['supplier_name'] as String? ?? '').isEmpty).length;
}

String _key(Object? h) =>
    (h ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Excel day number → yyyy-MM-dd (Excel counts from 30 Dec 1899).
String? _excelDate(Object? v) {
  if (v is num && v > 0) {
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: v.floor()));
    return d.toIso8601String().substring(0, 10);
  }
  if (v is String && v.trim().isNotEmpty) {
    final d = DateTime.tryParse(v.trim());
    return d?.toIso8601String().substring(0, 10);
  }
  return null;
}

/// Reads a stock export (.xlsx, first row = headers, one item per row).
/// Tag numbers are trimmed and upper-cased; they identify the items.
StockExport parseStockExport(Uint8List bytes) {
  final rows = readXlsxRows(bytes);
  if (rows.isEmpty) throw const FormatException('The sheet is empty');
  final header = rows.first;
  final fieldOf = <int, String>{};
  final seen = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final names = _columns[_key(header[i])];
    if (names == null) continue;
    final n = seen.update(_key(header[i]), (x) => x + 1, ifAbsent: () => 0);
    if (n < names.length) fieldOf[i] = names[n];
  }
  if (!fieldOf.containsValue('tag_no')) {
    throw const FormatException('No "Tag No" column found');
  }

  final byTag = <String, Map<String, Object?>>{};
  final dups = <String>{};
  var skipped = 0;
  for (final row in rows.skip(1)) {
    if (row.every((v) => v == null || v.toString().trim().isEmpty)) continue;
    final item = <String, Object?>{};
    fieldOf.forEach((i, field) {
      final v = i < row.length ? row[i] : null;
      if (field == 'entry_date') {
        item[field] = _excelDate(v);
      } else if (field == 'hallmark') {
        item[field] = (v ?? '').toString().trim().toUpperCase() == 'Y';
      } else if (_numbers.contains(field)) {
        final n = v is num ? v : num.tryParse((v ?? '').toString().trim());
        // Round away float noise (1743.0000000000002).
        item[field] = n == null ? 0 : (n * 1000).round() / 1000;
      } else {
        item[field] = (v ?? '').toString().trim();
      }
    });
    final tag = (item['tag_no'] as String? ?? '').toUpperCase();
    if (tag.isEmpty) {
      skipped++;
      continue;
    }
    item['tag_no'] = tag;
    item['supplier_name'] = (item['supplier_name'] as String? ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
    if (byTag.containsKey(tag)) dups.add(tag);
    byTag[tag] = item;
  }
  return StockExport(byTag.values.toList(), dups.toList(), skipped);
}
