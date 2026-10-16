import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/money.dart';
import '../../models/jewellery_input.dart';
import '../../ocr/image_enhancer.dart';
import '../../ocr/ocr_service.dart';
import '../../ocr/tag_parser.dart';
import '../../models/purity.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
  Uint8List? _preview;
  bool _enhance = true;
  bool _busy = false;
  String? _status;
  String? _error;
  ParsedTag? _parsed;

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

    // Optional crop so OCR focuses on the tag itself.
    final cropped = await _crop(file.path);
    final bytes = cropped != null
        ? await cropped.readAsBytes()
        : await file.readAsBytes();

    setState(() => _status = 'Preparing image…');
    try {
      _preview = await _enhancer.normalise(bytes);
    } catch (e) {
      setState(() {
        _status = null;
        _error = 'This image could not be read. Try another photo.';
      });
      return;
    }
    await _runOcr();
  }

  Future<CroppedFile?> _crop(String path) async {
    try {
      return await ImageCropper().cropImage(
        sourcePath: path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop to the tag',
            toolbarColor: AppColors.gold,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.gold,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
          ),
          IOSUiSettings(
            title: 'Crop to the tag',
            aspectRatioLockEnabled: false,
          ),
          WebUiSettings(context: context, presentStyle: WebPresentStyle.dialog),
        ],
      );
    } catch (e) {
      debugPrint('Crop unavailable, using full image: $e');
      return null;
    }
  }

  Future<void> _runOcr() async {
    final image = _preview;
    if (image == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _parsed = null;
      _status = _enhance ? 'Enhancing and reading text…' : 'Reading text…';
    });
    try {
      final input = _enhance ? await _enhancer.enhance(image) : image;
      _ocr ??= OcrService();
      final text = await _ocr!.recognize(input);
      final parsed = const TagParser().parse(text);
      setState(() {
        _parsed = parsed;
        _status = null;
        if (text.trim().isEmpty) {
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
        actions: const [RatesAction()],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (_preview == null) ..._intro() else ..._review(),
              if (_status != null) ...[
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
      height: 180,
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
    const SizedBox(height: 16),
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
    const SizedBox(height: 20),
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
          constraints: const BoxConstraints(maxHeight: 320),
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
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _capture(_lastSource ?? ImageSource.camera),
              icon: const Icon(Icons.replay),
              label: const Text('Retake'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _runOcr,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Rescan'),
            ),
          ),
        ],
      ),
      if (p != null) ...[
        const SizedBox(height: 20),
        const SectionTitle('Detected on tag'),
        _DetectedRow('Tag / item code', p.tagNumber, (v) => v),
        _DetectedRow('Item', p.itemName, (v) => v),
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
        _DetectedRow<double>(
          'Diamond weight',
          p.diamondWeight,
          (v) => '${v.toStringAsFixed(2)} ct',
        ),
        _DetectedRow<double>(
          'Other stone weight',
          p.stoneWeight,
          (v) => '${v.toStringAsFixed(2)} ct',
        ),
        _DetectedRow<double>(
          'Making charges',
          p.makingValue,
          (v) => p.makingMethod.value == MakingMethod.percentOfGold
              ? '${formatInput(v)}% of gold'
              : formatInr(v),
        ),
        _DetectedRow<double>(
          'Wastage',
          p.wastageValue,
          (v) => p.wastageMethod.value == WastageMethod.weight
              ? '${formatInput(v)} g'
              : '${formatInput(v)}%',
        ),
        const SizedBox(height: 8),
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
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}
