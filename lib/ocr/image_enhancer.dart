import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Basic pre-processing that helps OCR on printed tags: fixes EXIF rotation,
/// limits size, converts to greyscale, stretches contrast and sharpens.
class ImageEnhancer {
  const ImageEnhancer();

  Future<Uint8List> enhance(Uint8List bytes) => compute(_enhance, bytes);

  /// Normalises orientation/size only (no colour changes) for previews.
  Future<Uint8List> normalise(Uint8List bytes) => compute(_normalise, bytes);
}

const _maxSide = 2000;

img.Image _decode(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: _maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: _maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  return image;
}

Uint8List _normalise(Uint8List bytes) =>
    Uint8List.fromList(img.encodePng(_decode(bytes)));

Uint8List _enhance(Uint8List bytes) {
  var image = _decode(bytes);
  // Small tag photos: upscale so glyphs are tall enough for OCR.
  final longest = image.width > image.height ? image.width : image.height;
  if (longest < 1000) {
    image = img.copyResize(
      image,
      width: image.width * 2,
      height: image.height * 2,
      interpolation: img.Interpolation.cubic,
    );
  }
  image = img.grayscale(image);
  image = img.normalize(image, min: 0, max: 255);
  image = img.adjustColor(image, contrast: 1.25);
  image = img.convolution(image, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);
  return Uint8List.fromList(img.encodePng(image));
}
