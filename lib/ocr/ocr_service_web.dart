import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ocr_service.dart';

OcrService createOcrService() => PaddleOcrService();

/// Defined in web/index.html; runs PaddleOCR (see tool/web_ocr/entry.js).
@JS('jcRecognize')
external JSPromise<JSString> _recognize(JSString imageUrl);

/// In-browser OCR with PaddleOCR on ONNX Runtime Web. Finds text regions
/// first, so photo backgrounds are ignored, and corrects sideways or
/// upside-down tags itself.
class PaddleOcrService implements OcrService {
  @override
  String get engineName => 'PaddleOCR (browser)';

  @override
  bool get handlesRotation => true;

  @override
  bool get needsEnhancement => false;

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final blob = web.Blob(
      [imageBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    try {
      return (await _recognize(url.toJS).toDart).toDart;
    } catch (e) {
      throw OcrException(
        'The text reader could not run ($e). Check the internet connection '
        'for the first scan, or enter details manually.',
      );
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  @override
  Future<void> dispose() async {}
}
