import 'dart:typed_data';

import 'ocr_service_stub.dart'
    if (dart.library.io) 'ocr_service_mlkit.dart'
    if (dart.library.js_interop) 'ocr_service_web.dart'
    as impl;

/// Recognises printed text in an image.
abstract class OcrService {
  /// Platform-appropriate implementation: ML Kit (on-device) on Android/iOS,
  /// PaddleOCR (in-browser) on web.
  factory OcrService() => impl.createOcrService();

  String get engineName;

  /// True when the engine itself copes with sideways/upside-down images,
  /// so the caller need not retry other rotations.
  bool get handlesRotation;

  /// Whether greyscale/contrast/sharpen pre-processing helps this engine.
  bool get needsEnhancement;

  /// Returns the recognised text, line by line.
  Future<String> recognize(Uint8List imageBytes);

  /// Each piece of text with where it sits on the page, for pages laid out
  /// in columns (e.g. a handwritten sales register).
  Future<OcrPage> recognizeLayout(Uint8List imageBytes);

  Future<void> dispose();
}

class OcrException implements Exception {
  OcrException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A piece of recognised text and its box (in [OcrPage] pixels).
class OcrBox {
  const OcrBox(
    this.text, {
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 1,
  });

  final String text;
  final double left, top, right, bottom, confidence;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;

  factory OcrBox.fromJson(Map<String, dynamic> j) => OcrBox(
    j['text'] as String,
    left: (j['left'] as num).toDouble(),
    top: (j['top'] as num).toDouble(),
    right: (j['right'] as num).toDouble(),
    bottom: (j['bottom'] as num).toDouble(),
    confidence: (j['conf'] as num?)?.toDouble() ?? 1,
  );
}

/// Text found on a page, with positions.
class OcrPage {
  const OcrPage({
    required this.width,
    required this.height,
    required this.boxes,
  });

  final double width, height;
  final List<OcrBox> boxes;

  factory OcrPage.fromJson(Map<String, dynamic> j) => OcrPage(
    width: (j['width'] as num).toDouble(),
    height: (j['height'] as num).toDouble(),
    boxes: [
      for (final l in (j['lines'] as List))
        OcrBox.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
}
