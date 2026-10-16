import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ocr_service.dart';

OcrService createOcrService() => TesseractOcrService();

@JS('Tesseract')
external JSObject? get _tesseractGlobal;

/// Defined in web/index.html; wraps a reusable Tesseract.js worker.
@JS('jcRecognize')
external JSPromise<JSString> _recognize(JSString imageUrl);

/// In-browser OCR using Tesseract.js (loaded from web/index.html).
class TesseractOcrService implements OcrService {
  @override
  String get engineName => 'Tesseract.js (browser)';

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    if (_tesseractGlobal == null) {
      throw OcrException(
        'OCR engine could not be loaded. Connect to the internet for the '
        'first scan (or bundle OCR assets), or enter details manually.',
      );
    }
    final blob = web.Blob(
      [imageBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    try {
      return (await _recognize(url.toJS).toDart).toDart;
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  @override
  Future<void> dispose() async {}
}
