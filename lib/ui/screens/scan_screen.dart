import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/money.dart';
import '../../models/jewellery_input.dart';
import '../../ocr/image_enhancer.dart';
import '../../ocr/ocr_service.dart';
import '../../ocr/tag_parser.dart';
import '../../models/purity.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'crop_screen.dart';
import 'details_form_screen.dart';

/// Capture → crop → enhance → OCR → review detected fields.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _enhancer = const ImageEnhancer();
  OcrService? _ocr;

  ImageSource? _lastSource;

  /// Full captured image (orientation-normalised), kept for re-cropping.
  Uint8List? _original;

  /// Image sent to OCR (cropped/rotated).
  Uint8List? _preview;
  bool _enhance = true;
  bool _busy = false;
  String? _status;
  String? _error;
  ParsedTag? _parsed;
  String? _rotationNote;

  @override
  void dispose() {
    _ocr?.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    _lastSource = source;
    setState(() {
      _error = null;
      _status =
          'Opening ${source == ImageSource.camera ? 'camera' : 'gallery'}…';
    });
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.rear,
      );
    } on PlatformException catch (e) {
      setState(() => _status = null);
      if (!mounted) return;
      if (e.code.contains('access_denied') || e.code.contains('permission')) {
        await _showPermissionHelp(source);
      } else {
        setState(
          () =>
              _error = 'Could not open ${source.name}: ${e.message ?? e.code}',
        );
      }
      return;
    } catch (e) {
      setState(() {
        _status = null;
        _error = 'Could not open ${source.name}: $e';
      });
      return;
    }
    if (file == null) {
      setState(() => _status = null);
      return;
    }

    setState(() => _status = 'Preparing image…');
    try {
      _original = await _enhancer.normalise(await file.readAsBytes());
    } catch (e) {
      setState(() {
        _status = null;
        _error = 'This image could not be read. Try another photo.';
      });
      return;
    }
    await _cropAndScan();
  }

  /// Opens the crop step on the full captured image, then runs OCR.
  Future<void> _cropAndScan() async {
    final original = _original;
    if (original == null || !mounted) return;
    setState(() => _status = null);
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CropScreen(image: original)),
    );
    if (cropped == null || !mounted) return; // cancelled: keep current state
    _preview = cropped;
    await _runOcr();
  }

  /// Runs OCR. With [autoRotate], a sideways or upside-down photo is
  /// detected by also trying 90°/270°/180° when the first pass finds too
  /// little, keeping the orientation whose text yields the most fields.
  Future<void> _runOcr({bool autoRotate = true}) async {
    final image = _preview;
    if (image == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _parsed = null;
      _rotationNote = null;
      _status = _enhance ? 'Enhancing and reading text…' : 'Reading text…';
    });
    try {
      _ocr ??= OcrService();
      ({int deg, Uint8List img, String text, ParsedTag tag, int score})? best;
      for (final deg in autoRotate ? const [0, 90, 270, 180] : const [0]) {
        if (deg != 0) {
          setState(
            () => _status = 'Text unclear — trying the image rotated $deg°…',
          );
        }
        final rotated = deg == 0 ? image : await _enhancer.rotate(image, deg);
        final input = _enhance ? await _enhancer.enhance(rotated) : rotated;
        final text = await _ocr!.recognize(input);
        final tag = const TagParser().parse(text);
        final score = scoreParsedTag(tag);
        if (best == null || score > best.score) {
          best = (deg: deg, img: rotated, text: text, tag: tag, score: score);
        }
        if (tag.goldWeight.isFound && tag.purity.isFound) break;
      }
      final b = best!;
      setState(() {
        _parsed = b.tag;
        _status = null;
        if (b.deg != 0) {
          _preview = b.img;
          _rotationNote = 'Tag was sideways — rotated ${b.deg}° automatically';
        }
        if (b.text.trim().isEmpty) {
          _error =
              'No text found. Retake with the tag flat, in focus and well lit, '
              'or enter details manually.';
        }
      });
    } catch (e) {
      setState(() {
        _status = null;
        _error = 'Text recognition failed: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Manual 90° rotation (when automatic detection picks wrongly).
  Future<void> _rotateAndRescan() async {
    final image = _preview;
    if (image == null) return;
    setState(() => _status = 'Rotating…');
    _preview = await _enhancer.rotate(image, 90);
    await _runOcr(autoRotate: false);
  }

  Future<void> _showPermissionHelp(ImageSource source) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        source == ImageSource.camera
            ? 'Camera access needed'
            : 'Photo access needed',
      ),
      content: Text(
        'Allow ${source == ImageSource.camera ? 'camera' : 'photo library'} '
        'access for this app in your device Settings to scan tags. '
        'You can also enter jewellery details manually.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailsFormScreen(parsed: _parsed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Jewellery Tag'),
        actions: const [HistoryAction(), RatesAction()],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (_preview == null) ..._intro() else ..._review(),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_status!)),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                _Banner(
                  text: _error!,
                  color: AppColors.error,
                  icon: Icons.error_outline,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const DetailsFormScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Enter details manually'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _intro() => [
    Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: const Center(
        child: Icon(
          Icons.local_offer_outlined,
          size: 72,
          color: AppColors.gold,
        ),
      ),
    ),
    const SizedBox(height: 10),
    const Text(
      'Tips for a clean scan',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 6),
    const Text(
      '• Lay the tag flat and fill the frame with it\n'
      '• Use good light; avoid glare on laminated tags\n'
      '• Hold steady until the text is sharp\n'
      '• Crop to the printed area after capture',
      style: TextStyle(color: AppColors.muted, height: 1.6),
    ),
    const SizedBox(height: 12),
    FilledButton.icon(
      key: const Key('captureCamera'),
      onPressed: _busy ? null : () => _capture(ImageSource.camera),
      icon: const Icon(Icons.photo_camera),
      label: const Text('Open Camera'),
    ),
    const SizedBox(height: 10),
    OutlinedButton.icon(
      onPressed: _busy ? null : () => _capture(ImageSource.gallery),
      icon: const Icon(Icons.photo_library_outlined),
      label: Text(kIsWeb ? 'Upload Tag Image' : 'Choose from Gallery'),
    ),
  ];

  List<Widget> _review() {
    final p = _parsed;
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          constraints: const BoxConstraints(maxHeight: 240),
          child: Image.memory(_preview!, fit: BoxFit.contain),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enhance image for OCR'),
        subtitle: const Text('Greyscale, contrast and sharpening'),
        value: _enhance,
        onChanged: _busy ? null : (v) => setState(() => _enhance = v),
      ),
      if (_rotationNote != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(
                Icons.screen_rotation_alt,
                size: 18,
                color: AppColors.ok,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _rotationNote!,
                  style: const TextStyle(color: AppColors.ok),
                ),
              ),
            ],
          ),
        ),
      TileGrid(
        minTileWidth: 150,
        children: [
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _capture(_lastSource ?? ImageSource.camera),
            icon: const Icon(Icons.replay),
            label: const Text('Retake'),
          ),
          OutlinedButton.icon(
            key: const Key('recrop'),
            onPressed: _busy ? null : _cropAndScan,
            icon: const Icon(Icons.crop),
            label: const Text('Crop'),
          ),
          OutlinedButton.icon(
            key: const Key('rotate'),
            onPressed: _busy ? null : _rotateAndRescan,
            icon: const Icon(Icons.rotate_right),
            label: const Text('Rotate'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _runOcr,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Rescan'),
          ),
        ],
      ),
      if (p != null) ...[
        const SizedBox(height: 12),
        const SectionTitle('Detected on tag'),
        _DetectedRow('Tag / item code', p.tagNumber, (v) => v),
        _DetectedRow<Purity>('Gold purity', p.purity, (v) => v.label),
        _DetectedRow<double>(
          'Gold weight',
          p.goldWeight,
          (v) => '${v.toStringAsFixed(3)} g',
        ),
        _DetectedRow<double>(
          'Gross weight',
          p.grossWeight,
          (v) => '${v.toStringAsFixed(3)} g',
        ),
        if (p.stones.isEmpty)
          const _DetectedRow<double>(
            'Diamonds / stones',
            ParsedField.missing(),
            _noFormat,
          ),
        for (final st in p.stones)
          _DetectedRow<double>(
            '${st.label}${switch (st.kind.value) {
              StoneKind.stone => ' (stone)',
              StoneKind.polki => ' (polki)',
              _ => '',
            }}'
            '${st.code == null ? '' : ' · rate ${st.code}'}',
            st.kind.needsConfirmation
                ? ParsedField(
                    st.weight.value,
                    FieldConfidence.low,
                    note: st.kind.note,
                  )
                : st.weight,
            (v) => st.kind.value == StoneKind.stone
                ? '${formatInput(v)} pcs'
                : '${v.toStringAsFixed(2)} ct',
          ),
        if (p.weightBalance != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              p.weightBalance!.balances
                  ? '✓ Weights balance: ${p.weightBalance!.describe()}'
                  : '⚠ Weights do not balance: ${p.weightBalance!.describe()}',
              style: TextStyle(
                fontSize: 13,
                color: p.weightBalance!.balances
                    ? AppColors.ok
                    : AppColors.warn,
              ),
            ),
          ),
        _DetectedRow<double>(
          'Making charges',
          p.makingValue,
          (v) => switch (p.makingMethod.value) {
            MakingMethod.percentOfGold => '${formatInput(v)}% of gold',
            MakingMethod.fixed => '${formatInr(v)} fixed',
            _ => '${formatInr(v)}/g',
          },
        ),
        const SizedBox(height: 8),
        if (p.unreadStoneWeightG != null) ...[
          _Banner(
            text:
                'Gross − net weight is ${p.unreadStoneWeightG!.toStringAsFixed(3)} g '
                '(≈ ${(p.unreadStoneWeightG! / 0.2).toStringAsFixed(2)} ct), so this '
                'item likely has stones, but no stone lines were read. Tap Crop '
                'to frame only the tag and rescan, or add stone lines manually.',
            color: AppColors.warn,
            icon: Icons.diamond_outlined,
          ),
          const SizedBox(height: 8),
        ],
        if (p.uncertainFields.isNotEmpty || p.missingRequired.isNotEmpty)
          const _Banner(
            text:
                'Some values are unclear or missing. You will be asked to '
                'confirm them on the next screen.',
            color: AppColors.warn,
            icon: Icons.help_outline,
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Recognised text'),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tile,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                p.rawText.trim().isEmpty ? '(no text)' : p.rawText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('continueScan'),
          onPressed: _busy ? null : _continue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
        ),
      ],
    ];
  }
}

String _noFormat(double v) => '$v';

class _DetectedRow<T> extends StatelessWidget {
  const _DetectedRow(this.label, this.field, this.format);
  final String label;
  final ParsedField<T> field;
  final String Function(T) format;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (field.confidence) {
      FieldConfidence.high => (
        Icons.check_circle,
        AppColors.ok,
        format(field.value as T),
      ),
      FieldConfidence.low => (
        Icons.help,
        AppColors.warn,
        '${format(field.value as T)}  (confirm)',
      ),
      FieldConfidence.missing => (
        Icons.remove_circle_outline,
        AppColors.muted,
        'Not found',
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color == AppColors.muted
                    ? AppColors.muted
                    : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}
