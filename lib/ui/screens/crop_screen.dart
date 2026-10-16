import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ocr/image_enhancer.dart';
import '../theme.dart';

/// Built-in crop + rotate step (works offline on every platform).
/// Pops with the cropped PNG bytes, or `null` if cancelled.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.image});
  final Uint8List image;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _Drag { move, tl, tr, bl, br }

class _CropScreenState extends State<CropScreen> {
  final _enhancer = const ImageEnhancer();
  late Uint8List _image = widget.image;
  Size? _imageSize;
  // Crop rectangle as fractions of the image.
  Rect _crop = const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92);
  _Drag? _drag;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final codec = await ui.instantiateImageCodec(_image);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
    });
    frame.image.dispose();
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final rotated = await _enhancer.rotate(_image, 90);
    if (!mounted) return;
    setState(() {
      _image = rotated;
      _imageSize = null;
      // Rotate the crop box with the image (clockwise).
      _crop = Rect.fromLTRB(
        1 - _crop.bottom,
        _crop.left,
        1 - _crop.top,
        _crop.right,
      );
      _busy = false;
    });
    await _loadSize();
  }

  Future<void> _done({required bool crop}) async {
    setState(() => _busy = true);
    final out = crop ? await _enhancer.crop(_image, _crop) : _image;
    if (mounted) Navigator.of(context).pop(out);
  }

  /// Where the image is drawn inside [box] (BoxFit.contain).
  Rect _imageRect(Size box) {
    final s = _imageSize!;
    final scale = (box.width / s.width) < (box.height / s.height)
        ? box.width / s.width
        : box.height / s.height;
    final w = s.width * scale, h = s.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _onPanStart(Offset p, Rect img) {
    final r = _toScreen(_crop, img);
    const grab = 32.0;
    final corners = {
      _Drag.tl: r.topLeft,
      _Drag.tr: r.topRight,
      _Drag.bl: r.bottomLeft,
      _Drag.br: r.bottomRight,
    };
    for (final e in corners.entries) {
      if ((e.value - p).distance <= grab) {
        _drag = e.key;
        return;
      }
    }
    _drag = r.inflate(8).contains(p) ? _Drag.move : null;
  }

  void _onPanUpdate(Offset delta, Rect img) {
    final d = _drag;
    if (d == null) return;
    final dx = delta.dx / img.width, dy = delta.dy / img.height;
    const minSize = 0.08;
    var c = _crop;
    switch (d) {
      case _Drag.move:
        final nx = (c.left + dx).clamp(0.0, 1 - c.width);
        final ny = (c.top + dy).clamp(0.0, 1 - c.height);
        c = Rect.fromLTWH(nx, ny, c.width, c.height);
      case _Drag.tl:
        c = Rect.fromLTRB(
          (c.left + dx).clamp(0.0, c.right - minSize),
          (c.top + dy).clamp(0.0, c.bottom - minSize),
          c.right,
          c.bottom,
        );
      case _Drag.tr:
        c = Rect.fromLTRB(
          c.left,
          (c.top + dy).clamp(0.0, c.bottom - minSize),
          (c.right + dx).clamp(c.left + minSize, 1.0),
          c.bottom,
        );
      case _Drag.bl:
        c = Rect.fromLTRB(
          (c.left + dx).clamp(0.0, c.right - minSize),
          c.top,
          c.right,
          (c.bottom + dy).clamp(c.top + minSize, 1.0),
        );
      case _Drag.br:
        c = Rect.fromLTRB(
          c.left,
          c.top,
          (c.right + dx).clamp(c.left + minSize, 1.0),
          (c.bottom + dy).clamp(c.top + minSize, 1.0),
        );
    }
    setState(() => _crop = c);
  }

  static Rect _toScreen(Rect f, Rect img) => Rect.fromLTRB(
    img.left + f.left * img.width,
    img.top + f.top * img.height,
    img.left + f.right * img.width,
    img.top + f.bottom * img.height,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Crop to the tag',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Drag the corners so only the printed tag is inside the box. '
                'Background patterns (wood, cloth) confuse text recognition.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: _imageSize == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, c) {
                        final box = Size(c.maxWidth, c.maxHeight);
                        final img = _imageRect(box);
                        return GestureDetector(
                          key: const Key('cropArea'),
                          onPanStart: (d) => _onPanStart(d.localPosition, img),
                          onPanUpdate: (d) => _onPanUpdate(d.delta, img),
                          onPanEnd: (_) => _drag = null,
                          child: Stack(
                            children: [
                              Positioned.fromRect(
                                rect: img,
                                child: Image.memory(_image, fit: BoxFit.fill),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _CropPainter(_toScreen(_crop, img)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    key: const Key('cropRotate'),
                    tooltip: 'Rotate 90°',
                    onPressed: _busy ? null : _rotate,
                    icon: const Icon(Icons.rotate_right),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: _busy ? null : () => _done(crop: false),
                      child: const Text('Use full image'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const Key('useCrop'),
                      onPressed: _busy || _imageSize == null
                          ? null
                          : () => _done(crop: true),
                      child: const Text('Use crop'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(rect),
      ),
      shade,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.goldSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final handle = Paint()..color = AppColors.gold;
    for (final p in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(p, 10, handle);
      canvas.drawCircle(
        p,
        10,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}
