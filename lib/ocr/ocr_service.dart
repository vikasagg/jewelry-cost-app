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

  Future<void> dispose();
}

class OcrException implements Exception {
  OcrException(this.message);
  final String message;
  @override
  String toString() => message;
}
