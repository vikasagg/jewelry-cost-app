import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_service.dart';

OcrService createOcrService() => MlKitOcrService();

/// On-device OCR with Google ML Kit (Latin script). Works offline.
class MlKitOcrService implements OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  String get engineName => 'ML Kit (on-device)';

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw OcrException('Camera OCR is available on Android, iOS and web.');
    }
    final dir = await Directory.systemTemp.createTemp('jc_ocr');
    final file = File('${dir.path}/tag.png');
    try {
      await file.writeAsBytes(imageBytes, flush: true);
      final result = await _recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      // Rebuild text in reading order: blocks top-to-bottom, lines within.
      final lines = <TextLine>[for (final b in result.blocks) ...b.lines]
        ..sort((a, b) {
          final dy = a.boundingBox.top - b.boundingBox.top;
          if (dy.abs() > a.boundingBox.height / 2) return dy.sign.toInt();
          return (a.boundingBox.left - b.boundingBox.left).sign.toInt();
        });
      return _mergeRows(lines);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Joins lines that sit on the same visual row (e.g. "GW" … "10.250 g").
  String _mergeRows(List<TextLine> lines) {
    final rows = <List<TextLine>>[];
    for (final l in lines) {
      if (rows.isNotEmpty) {
        final ref = rows.last.first.boundingBox;
        final centre = l.boundingBox.center.dy;
        if (centre > ref.top && centre < ref.bottom) {
          rows.last.add(l);
          continue;
        }
      }
      rows.add([l]);
    }
    return rows
        .map(
          (r) =>
              (r..sort(
                    (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left),
                  ))
                  .map((l) => l.text)
                  .join('  '),
        )
        .join('\n');
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
