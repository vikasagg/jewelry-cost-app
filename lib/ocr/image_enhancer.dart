import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:image/image.dart' as img;

/// Basic pre-processing that helps OCR on printed tags: fixes EXIF rotation,
/// limits size, converts to greyscale, stretches contrast and sharpens.
class ImageEnhancer {
  const ImageEnhancer();

  Future<Uint8List> enhance(Uint8List bytes) => compute(_enhance, bytes);

  /// Normalises orientation/size only (no colour changes) for previews.
  Future<Uint8List> normalise(Uint8List bytes) => compute(_normalise, bytes);

  /// Crops to a rectangle given as fractions (0–1) of width/height.
  Future<Uint8List> crop(Uint8List bytes, Rect fraction) => compute(_crop, (
    bytes,
    fraction.left,
    fraction.top,
    fraction.width,
    fraction.height,
  ));

  /// Rotates clockwise by [degrees] (90, 180 or 270).
  Future<Uint8List> rotate(Uint8List bytes, int degrees) =>
      compute(_rotate, (bytes, degrees));
}

Uint8List _crop((Uint8List, double, double, double, double) a) {
  final image = img.decodeImage(a.$1);
  if (image == null) throw const FormatException('Unsupported image format');
  final x = (a.$2 * image.width).round().clamp(0, image.width - 1);
  final y = (a.$3 * image.height).round().clamp(0, image.height - 1);
  final w = (a.$4 * image.width).round().clamp(1, image.width - x);
  final h = (a.$5 * image.height).round().clamp(1, image.height - y);
  return Uint8List.fromList(
    img.encodePng(img.copyCrop(image, x: x, y: y, width: w, height: h)),
  );
}

Uint8List _rotate((Uint8List, int) args) {
  final image = img.decodeImage(args.$1);
  if (image == null) throw const FormatException('Unsupported image format');
  return Uint8List.fromList(
    img.encodePng(img.copyRotate(image, angle: args.$2)),
  );
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
