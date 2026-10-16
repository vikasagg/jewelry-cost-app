import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'ocr_service.dart';

OcrService createOcrService() => MlKitOcrService();

/// On-device OCR with Google ML Kit (Latin script). Works offline.
///
/// The image is handed to ML Kit as raw RGBA pixels rather than a temporary
/// file: decoding a file path inside ML Kit failed on some Android devices
/// with a NullPointerException.
class MlKitOcrService implements OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  String get engineName => 'ML Kit (on-device)';

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw OcrException('Camera OCR is available on Android, iOS and web.');
    }
    final pixels = await compute(_toRgba, imageBytes);
    final RecognizedText result;
    try {
      result = await _recognizer.processImage(
        InputImage.fromBitmap(
          bitmap: pixels.rgba,
          width: pixels.width,
          height: pixels.height,
        ),
      );
    } catch (e) {
      throw OcrException('ML Kit could not read the image: $e');
    }
    // Rebuild text in reading order: lines top-to-bottom, left-to-right.
    final lines = <TextLine>[for (final b in result.blocks) ...b.lines]
      ..sort((a, b) {
        final dy = a.boundingBox.top - b.boundingBox.top;
        if (dy.abs() > a.boundingBox.height / 2) return dy.sign.toInt();
        return (a.boundingBox.left - b.boundingBox.left).sign.toInt();
      });
    return _mergeRows(lines);
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

typedef _Rgba = ({Uint8List rgba, int width, int height});

_Rgba _toRgba(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
  return (
    rgba: rgba.getBytes(order: img.ChannelOrder.rgba),
    width: rgba.width,
    height: rgba.height,
  );
}
