import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/jewellery_input.dart';
import '../../ocr/image_enhancer.dart';
import '../../ocr/ocr_service.dart';
import '../../ocr/tag_parser.dart';
import '../../models/purity.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/price_icons.dart';
import 'crop_screen.dart';
import 'details_form_screen.dart';

/// Capture → crop → enhance → OCR → review detected fields.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.initialImage, this.initialResult});

  /// Tests only: start on the review step with this image and OCR result.
  @visibleForTesting
  final Uint8List? initialImage;
  @visibleForTesting
  final ParsedTag? initialResult;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _enhancer = const ImageEnhancer();
  OcrService? _ocrService;
  OcrService get _ocr => _ocrService ??= OcrService();

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
  void initState() {
    super.initState();
    _preview = widget.initialImage;
    _parsed = widget.initialResult;
    if (_parsed != null) _fillFields(_parsed!);
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _ocrService?.dispose();
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
        maxWidth: 1600,
        maxHeight: 1600,
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
  /// little, keeping the orientation whose text yields the most fields
  /// (engines that correct orientation themselves need only one pass).
  Future<void> _runOcr({bool autoRotate = true}) async {
    final image = _preview;
    if (image == null) return;
    final enhance = _enhance && _ocr.needsEnhancement;
    setState(() {
      _busy = true;
      _error = null;
      _parsed = null;
      _rotationNote = null;
      _status = enhance ? 'Enhancing and reading text…' : 'Reading text…';
    });
    try {
      final rotations = autoRotate && !_ocr.handlesRotation
          ? const [0, 90, 270, 180]
          : const [0];
      ({int deg, Uint8List img, String text, ParsedTag tag, int score})? best;
      for (final deg in rotations) {
        if (deg != 0) {
          setState(
            () => _status = 'Text unclear — trying the image rotated $deg°…',
          );
        }
        final rotated = deg == 0 ? image : await _enhancer.rotate(image, deg);
        final input = enhance ? await _enhancer.enhance(rotated) : rotated;
        final text = await _ocr.recognize(input);
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
        _fillFields(b.tag);
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

  /// Values still to be checked here: unclear readings (one entry per
  /// stone line) and a missing gold weight.
  Set<String> _pending(ParsedTag p) => {
    for (final k in p.uncertainFields.keys)
      if (k != 'itemName') // not shown or used
        k.startsWith('stone.') ? k.substring(0, k.lastIndexOf('.')) : k,
    if (!p.goldWeight.isFound) 'goldWeight',
  };

  void _confirm(String key, [Object? value]) =>
      setState(() => _parsed = _parsed!.confirm(key, value));

  void _confirmAll() => setState(() {
    for (final k in _pending(_parsed!)) {
      _parsed = _parsed!.confirm(k);
    }
  });

  Future<void> _editStone(int i, ParsedStone st) async {
    final c = TextEditingController(text: formatInput(st.weight.value));
    var kind = st.kind.value ?? StoneKind.diamond;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(st.label),
          // Fixed width: SegmentedButton cannot size itself intrinsically.
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<StoneKind>(
                  showSelectedIcon: false,
                  segments: [
                    for (final k in StoneKind.values)
                      ButtonSegment(value: k, label: Text(k.label)),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setLocal(() => kind = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('editValue'),
                  controller: c,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: kind == StoneKind.stone ? 'Pieces' : 'Weight',
                    suffixText: kind == StoneKind.stone ? 'pcs' : 'ct',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('editSave'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final w = parseNumber(c.text);
    if (ok == true) {
      final weight = w == null || w.isNaN || w <= 0 ? null : w;
      _confirm('stone.$i', (weight, kind));
      if (weight != null) _fields['stone.$i']?.text = formatInput(weight);
    }
  }

  Future<void> _continue() async {
    var parsed = _parsed!;
    if (parsed.itemName.needsConfirmation) parsed = parsed.confirm('itemName');
    // A small copy of the photo travels with the estimate into history.
    Uint8List? thumb;
    try {
      thumb = await _enhancer.thumbnail(_preview!);
    } catch (_) {
      thumb = null; // the estimate still works without a photo
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsFormScreen(parsed: parsed, image: thumb),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _preview == null ? 'Scan Jewellery Tag' : 'Extracted Details',
        ),
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
    final pending = p == null ? const <String>{} : _pending(p);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  child: InteractiveViewer(child: Image.memory(_preview!)),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 130,
                  color: AppColors.tile,
                  child: Image.memory(
                    _preview!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    cacheWidth: 600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  key: const Key('newScan'),
                  onPressed: _busy
                      ? null
                      : () => _capture(_lastSource ?? ImageSource.camera),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan Again'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('recrop'),
                  onPressed: _busy ? null : _cropAndScan,
                  icon: const Icon(Icons.crop),
                  label: const Text('Crop'),
                ),
              ],
            ),
          ),
        ],
      ),
      if (_ocr.needsEnhancement)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enhance image for OCR'),
          value: _enhance,
          onChanged: _busy ? null : (v) => setState(() => _enhance = v),
        ),
      if (_rotationNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _rotationNote!,
            style: const TextStyle(color: AppColors.ok, fontSize: 13),
          ),
        ),
      if (p != null) ...[
        const SizedBox(height: 14),
        const SectionTitle('Extracted Information'),
        if (pending.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Check the highlighted values: correct them, or tap ✓ if right.',
              key: Key('confirmHint'),
              style: TextStyle(color: AppColors.warn),
            ),
          ),
        _FieldRow(
          icon: PriceIcons.tag,
          label: 'Item / Tag No.',
          field: p.tagNumber,
          fieldKey: 'tagNumber',
          onConfirm: () => _confirm('tagNumber'),
          child: _textField('tagNumber', number: false, hint: 'Auto (DJ-)'),
        ),
        _FieldRow(
          icon: PriceIcons.weight,
          label: 'Gold Weight (g)',
          field: p.goldWeight,
          fieldKey: 'goldWeight',
          required: true,
          onConfirm: () => _confirm('goldWeight'),
          child: _textField('goldWeight'),
        ),
        _FieldRow(
          icon: PriceIcons.purity,
          label: 'Gold Purity',
          field: p.purity,
          fieldKey: 'purity',
          missingNote: 'Not on the tag — 18K will be used',
          onConfirm: () => _confirm('purity'),
          child: DropdownButtonFormField<Purity>(
            key: const Key('field_purity'),
            initialValue: p.purity.value,
            isDense: true,
            hint: const Text('18K'),
            items: [
              for (final x in Purity.values.reversed)
                DropdownMenuItem(value: x, child: Text(x.label)),
            ],
            onChanged: (v) {
              if (v != null) _confirm('purity', v);
            },
          ),
        ),
        _FieldRow(
          icon: PriceIcons.grossWeight,
          label: 'Gross Weight (g)',
          field: p.grossWeight,
          fieldKey: 'grossWeight',
          onConfirm: () => _confirm('grossWeight'),
          child: _textField('grossWeight', hint: 'Optional'),
        ),
        for (var i = 0; i < p.stones.length; i++)
          _FieldRow(
            icon: switch (p.stones[i].kind.value) {
              StoneKind.stone => PriceIcons.stone,
              StoneKind.polki => PriceIcons.polki,
              _ => PriceIcons.diamond,
            },
            label:
                '${p.stones[i].label}${p.stones[i].code == null ? '' : ' · ${p.stones[i].code}'}'
                ' (${p.stones[i].kind.value == StoneKind.stone ? 'pcs' : 'ct'})',
            sublabel: p.stones[i].kind.value?.label,
            onLabelTap: () => _editStone(i, p.stones[i]),
            labelKey: 'edit_stone.$i',
            field: p.stones[i].kind.needsConfirmation
                ? ParsedField(
                    p.stones[i].weight.value,
                    FieldConfidence.low,
                    note: p.stones[i].kind.note,
                  )
                : p.stones[i].weight,
            fieldKey: 'stone.$i',
            onConfirm: () => _confirm('stone.$i'),
            child: _textField('stone.$i'),
          ),
        if (p.makingValue.isFound)
          _FieldRow(
            icon: PriceIcons.labour,
            label: switch (p.makingMethod.value) {
              MakingMethod.percentOfGold => 'Making (% of gold)',
              MakingMethod.fixed => 'Making (₹ fixed)',
              _ => 'Making (₹ per g)',
            },
            field: p.makingValue,
            fieldKey: 'makingValue',
            onConfirm: () => _confirm('makingValue'),
            child: _textField('makingValue'),
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
        if (p.stones.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No diamond, stone or polki lines on this tag.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        if (p.unreadStoneWeightG != null) ...[
          const SizedBox(height: 8),
          _Banner(
            text:
                'Gross − net weight is ${p.unreadStoneWeightG!.toStringAsFixed(3)} g '
                '(≈ ${(p.unreadStoneWeightG! / 0.2).toStringAsFixed(2)} ct), so this '
                'item likely has stones, but no stone lines were read. Tap Crop '
                'to frame only the tag and rescan, or add stone lines on the next '
                'screen.',
            color: AppColors.warn,
            icon: Icons.diamond_outlined,
          ),
        ],
        // A missing gold weight must be typed in, so "Confirm all" waits.
        if (pending.length > 1 && p.goldWeight.isFound)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('confirmAll'),
              onPressed: _busy ? null : _confirmAll,
              icon: const Icon(Icons.done_all),
              label: Text('Confirm all ${pending.length}'),
            ),
          ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('continueScan'),
          style: FilledButton.styleFrom(minimumSize: const Size(56, 48)),
          onPressed: _busy || pending.isNotEmpty ? null : _continue,
          child: Text(
            pending.isEmpty
                ? 'Continue to Calculate'
                : 'Confirm ${pending.length} '
                      '${pending.length == 1 ? 'value' : 'values'} to continue',
          ),
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
      ],
    ];
  }

  /// Editable value boxes, filled from the scan; typing confirms the value.
  final _fields = <String, TextEditingController>{};

  /// Puts the scanned values into the edit boxes.
  void _fillFields(ParsedTag p) {
    String num(double? v) => formatInput(v);
    final values = <String, String>{
      'tagNumber': p.tagNumber.value ?? '',
      'goldWeight': num(p.goldWeight.value),
      'grossWeight': num(p.grossWeight.value),
      'makingValue': num(p.makingValue.value),
      for (var i = 0; i < p.stones.length; i++)
        'stone.$i': num(p.stones[i].weight.value),
    };
    for (final c in _fields.values) {
      c.dispose();
    }
    _fields
      ..clear()
      ..addAll({
        for (final e in values.entries)
          e.key: TextEditingController(text: e.value),
      });
  }

  Widget _textField(String key, {bool number = true, String? hint}) {
    final c = _fields.putIfAbsent(key, TextEditingController.new);
    return TextField(
      key: Key('field_$key'),
      controller: c,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(hintText: hint),
      onChanged: (t) {
        if (!number) {
          if (t.trim().isNotEmpty) _confirm(key, t.trim());
          return;
        }
        final v = parseNumber(t);
        if (v == null || v.isNaN || v <= 0) return;
        _confirm(key, key.startsWith('stone.') ? (v, null) : v);
      },
    );
  }
}

/// One extracted value: icon square, label and an edit box. Unclear
/// values get a gold border, the reason and a ✓ to confirm as read.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.field,
    required this.fieldKey,
    required this.child,
    this.onConfirm,
    this.required = false,
    this.missingNote,
    this.sublabel,
    this.onLabelTap,
    this.labelKey,
  });
  final Widget icon;
  final String label;
  final ParsedField<dynamic> field;
  final String fieldKey;
  final Widget child;
  final VoidCallback? onConfirm;
  final bool required;
  final String? missingNote;
  final String? sublabel;
  final VoidCallback? onLabelTap;
  final String? labelKey;

  @override
  Widget build(BuildContext context) {
    final unclear = field.needsConfirmation;
    final mustEnter = required && !field.isFound;
    final note = unclear
        ? field.note
        : mustEnter
        ? 'Not found on the tag — enter it'
        : !field.isFound
        ? missingNote
        : null;
    final highlight = unclear || mustEnter;
    Widget labelText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        if (sublabel != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sublabel!,
                style: const TextStyle(fontSize: 12, color: AppColors.goldDeep),
              ),
              if (onLabelTap != null)
                const Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: AppColors.goldDeep,
                ),
            ],
          ),
      ],
    );
    if (onLabelTap != null) {
      labelText = InkWell(
        key: labelKey == null ? null : Key(labelKey!),
        onTap: onLabelTap,
        child: labelText,
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: highlight ? const EdgeInsets.all(6) : EdgeInsets.zero,
      decoration: highlight
          ? BoxDecoration(
              color: AppColors.warnSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warn.withValues(alpha: 0.5)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconSquare(icon: icon, size: 38),
              const SizedBox(width: 10),
              Expanded(flex: 5, child: labelText),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: child),
              if (unclear)
                IconButton(
                  key: Key('confirm_$fieldKey'),
                  tooltip: 'Confirm as read',
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_circle, color: AppColors.gold),
                ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 3),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  color: highlight ? AppColors.warn : AppColors.muted,
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
