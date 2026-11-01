import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_state.dart';
import '../../../ocr/image_enhancer.dart';
import '../../../ocr/ocr_service.dart';
import '../../../reports/register_image.dart';
import '../../../reports/sales_register.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Today's Sales: photograph a page of the handwritten customer register,
/// check the rows the app reads, then share a clean register image.
class SalesRegisterScreen extends StatefulWidget {
  const SalesRegisterScreen({super.key, this.ocr, this.pickImage});

  /// For tests: the text reader and the photo picker.
  final OcrService? ocr;
  final Future<Uint8List?> Function(ImageSource source)? pickImage;

  @override
  State<SalesRegisterScreen> createState() => _SalesRegisterScreenState();
}

class _SalesRegisterScreenState extends State<SalesRegisterScreen> {
  late final SalesRegisterBook _book = AppScope.read(context).sales;
  late String _date = _book.today;
  late SalesRegister _reg = _book.byDate(_date);
  OcrService? _ocr;
  String? _busy;

  @override
  void dispose() {
    if (widget.ocr == null) _ocr?.dispose();
    super.dispose();
  }

  Future<void> _save(SalesRegister r) async {
    setState(() => _reg = r);
    await _book.save(r);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDate() async {
    final fmt = DateFormat('yyyy-MM-dd');
    final picked = await showDatePicker(
      context: context,
      initialDate: fmt.parse(_date),
      firstDate: DateTime(2020),
      lastDate: fmt.parse(_book.today),
      helpText: 'Register date',
    );
    if (picked == null) return;
    setState(() {
      _date = fmt.format(picked);
      _reg = _book.byDate(_date);
    });
  }

  Future<Uint8List?> _photo(ImageSource source) async {
    if (widget.pickImage != null) return widget.pickImage!(source);
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return null;
    return const ImageEnhancer().normalise(await file.readAsBytes());
  }

  /// Reads a register page and adds its rows after the ones already here.
  Future<void> _scan(ImageSource source) async {
    Uint8List? bytes;
    try {
      bytes = await _photo(source);
    } on PlatformException catch (e) {
      _snack('Could not open the ${source.name}: ${e.message ?? e.code}');
      return;
    }
    if (bytes == null || !mounted) return;
    setState(() => _busy = 'Reading the register page…');
    try {
      final ocr = widget.ocr ?? (_ocr ??= OcrService());
      final page = await ocr.recognizeLayout(bytes);
      final vocab = _book.vocabulary();
      final rows = parseRegisterPage(
        page,
        startNo: _reg.nextNumber,
        knownNames: vocab.names,
        knownItems: vocab.items,
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        _snack('No register lines found. Try a closer, brighter photo.');
      } else {
        final part = _reg.nextPart;
        final m = _reg.mergePart(rows);
        await _save(m.register);
        _snack(
          'Part $part: ${m.added} line${m.added == 1 ? '' : 's'} added'
          '${m.skipped == 0 ? '' : ', ${m.skipped} already listed skipped'}'
          ' — please check each one.',
        );
      }
    } catch (e) {
      _snack('Could not read the page: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _partAction(int part, String action) async {
    if (action == 'first') {
      await _save(_reg.movePartFirst(part));
      _snack('Part $part moved to the top; lines renumbered.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove part $part?'),
        content: Text(
          'Its ${_reg.parts[part]} line(s) are removed and the rest are '
          'renumbered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('removePartOk'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _save(_reg.removePart(part));
  }

  /// Deletes one line (with Undo) and renumbers the rest.
  Future<void> _delete(int index) async {
    final before = _reg;
    final gone = _reg.entries[index];
    await _save(
      _reg.copyWith(entries: [..._reg.entries]..removeAt(index)).renumbered(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${gone.name.isEmpty ? 'line ${gone.no}' : gone.name}',
          ),
          action: SnackBarAction(label: 'Undo', onPressed: () => _save(before)),
        ),
      );
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all lines?'),
        content: Text(
          'All ${_reg.entries.length} lines of ${_reg.dateLabel} are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('clearAllOk'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok == true) await _save(_reg.copyWith(entries: const []));
  }

  Future<void> _edit(int? index) async {
    final e = index == null
        ? SalesEntry(no: _reg.nextNumber)
        : _reg.entries[index];
    final vocab = _book.vocabulary();
    final result = await showSalesEntryDialog(
      context,
      e,
      items: {...vocab.items, ...registerItems}.toList(),
      isNew: index == null,
    );
    if (result == null) return;
    final list = [..._reg.entries];
    if (result.delete) {
      list.removeAt(index!);
    } else if (index == null) {
      list.add(result.entry);
    } else {
      list[index] = result.entry;
    }
    list.sort((a, b) => a.no.compareTo(b.no));
    await _save(_reg.copyWith(entries: list));
  }

  Future<void> _createImage() async {
    if (_reg.entries.isEmpty) {
      _snack('Add the register lines first.');
      return;
    }
    if (_reg.unchecked > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lines not checked yet'),
          content: Text(
            '${_reg.unchecked} line${_reg.unchecked == 1 ? '' : 's'} read '
            'from the photo ha${_reg.unchecked == 1 ? 's' : 've'} not been '
            'checked. Create the report anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Check first'),
            ),
            FilledButton(
              key: const Key('createAnyway'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    // A "Deleted … Undo" message would cover the report's buttons.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegisterImageScreen(register: _reg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _reg;
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Sales")),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              OutlinedButton.icon(
                key: const Key('registerDate'),
                onPressed: _busy == null ? _pickDate : null,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  _date == _book.today ? 'Today · ${r.dateLabel}' : r.dateLabel,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Photograph a register page',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.entries.isEmpty
                            ? 'Hold the phone straight over the page, in good '
                                  'light. The lines are read and listed below '
                                  'for you to check.'
                            : 'Page in two parts? Photograph the next '
                                  'part: lines already listed are skipped, '
                                  'the rest continue from No. ${r.nextNumber}.',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 10),
                      if (_busy != null) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 6),
                        Text(_busy!, key: const Key('registerBusy')),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('registerCamera'),
                                onPressed: () => _scan(ImageSource.camera),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: const Text('Camera'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('registerGallery'),
                                onPressed: () => _scan(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Gallery'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (r.parts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Photos merged:',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    for (final p in r.parts.entries)
                      PopupMenuButton<String>(
                        key: Key('registerPart_${p.key}'),
                        tooltip: 'Part ${p.key}',
                        onSelected: (a) => _partAction(p.key, a),
                        itemBuilder: (_) => [
                          if (r.parts.length > 1)
                            const PopupMenuItem(
                              value: 'first',
                              child: Text('Move to top (renumber)'),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove this part'),
                          ),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.photo_outlined, size: 18),
                          label: Text(
                            'Part ${p.key} · ${p.value} line${p.value == 1 ? '' : 's'}',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SectionTitle('Register lines (${r.entries.length})'),
                  ),
                  if (r.entries.isNotEmpty)
                    TextButton.icon(
                      key: const Key('registerClearAll'),
                      onPressed: _clearAll,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Clear all'),
                    ),
                  TextButton.icon(
                    key: const Key('registerAddRow'),
                    onPressed: () => _edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add line'),
                  ),
                ],
              ),
              if (r.unchecked > 0)
                Container(
                  key: const Key('registerUnchecked'),
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warnSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${r.unchecked} line${r.unchecked == 1 ? '' : 's'} read '
                    'from the photo — tap each to check or correct it.',
                  ),
                ),
              if (r.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No lines yet. Photograph the register page, or add '
                    'lines by hand.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              for (var i = 0; i < r.entries.length; i++)
                _EntryTile(
                  key: Key('registerRow_$i'),
                  index: i,
                  entry: r.entries[i],
                  onTap: () => _edit(i),
                  onDelete: () => _delete(i),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('createRegisterImage'),
                onPressed: r.entries.isEmpty ? null : _createImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Create report image'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    super.key,
    required this.index,
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });
  final int index;
  final SalesEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: e.checked ? Colors.transparent : AppColors.warn,
          width: 1.5,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.only(left: 2, right: 12),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('registerDelete_$index'),
              tooltip: 'Delete this line',
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: onDelete,
            ),
            CircleAvatar(
              backgroundColor: e.checked
                  ? AppColors.goldSoft
                  : AppColors.warnSoft,
              child: Text(
                e.numberLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        title: Text(
          e.name.isEmpty ? '— name —' : e.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            e.item.isEmpty ? '— item —' : e.item,
            if (e.mobile.isNotEmpty) e.mobile,
          ].join(' · '),
        ),
        trailing: Icon(
          e.checked ? Icons.edit_outlined : Icons.error_outline,
          color: e.checked ? AppColors.muted : AppColors.warn,
        ),
      ),
    );
  }
}

/// Edits one register line; returns it (checked) or a delete request.
Future<({SalesEntry entry, bool delete})?> showSalesEntryDialog(
  BuildContext context,
  SalesEntry e, {
  required List<String> items,
  bool isNew = false,
}) {
  // Controllers are left to the garbage collector: disposing them as the
  // dialog pops breaks its closing animation.
  final no = TextEditingController(text: '${e.no}');
  final name = TextEditingController(text: e.name);
  final mobile = TextEditingController(text: e.mobile);
  final item = TextEditingController(text: e.item);
  var type = e.type;
  return showDialog<({SalesEntry entry, bool delete})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(isNew ? 'Add register line' : 'Register line'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        key: const Key('entryNo'),
                        controller: no,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(labelText: 'No.'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final t in const ['R', 'N'])
                            ChoiceChip(
                              key: Key('entryType_$t'),
                              label: Text(t == 'R' ? 'R · repeat' : 'N · new'),
                              selected: type == t,
                              onSelected: (on) =>
                                  setLocal(() => type = on ? t : ''),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: const Key('entryName'),
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  key: const Key('entryMobile'),
                  controller: mobile,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(labelText: 'Mobile'),
                ),
                TextField(
                  key: const Key('entryItem'),
                  controller: item,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Item'),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: -6,
                  children: [
                    for (final i in items.take(12))
                      ActionChip(
                        label: Text(i, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setLocal(() => item.text = i),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isNew)
            TextButton(
              key: const Key('entryDelete'),
              onPressed: () => Navigator.pop(context, (entry: e, delete: true)),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('entryOk'),
            onPressed: () => Navigator.pop(context, (
              entry: e.copyWith(
                no: int.tryParse(no.text) ?? e.no,
                type: type,
                name: name.text.trim(),
                mobile: mobile.text.trim(),
                item: item.text.trim(),
                checked: true,
              ),
              delete: false,
            )),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

/// The clean register image, ready to share.
class RegisterImageScreen extends StatefulWidget {
  const RegisterImageScreen({super.key, required this.register});
  final SalesRegister register;

  @override
  State<RegisterImageScreen> createState() => _RegisterImageScreenState();
}

class _RegisterImageScreenState extends State<RegisterImageScreen> {
  // Drawn up front: browsers (iPhone Safari) only open the share sheet
  // straight after a tap.
  late final Future<Uint8List> _png = renderRegisterPng(widget.register);

  String get _fileName => 'customer-register-${widget.register.date}.png';

  String get _caption => 'Customer register — ${widget.register.dateLabel}';

  /// Android app: WhatsApp opens with the image attached and asks which
  /// chat to send it to. iPhone and browsers: the share sheet.
  Future<void> _whatsApp(Uint8List png) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final r = await const MethodChannel('damiyaas/whatsapp')
            .invokeMethod<String>('sendFile', {
              'bytes': png,
              'name': _fileName,
              'phone': '',
              'text': _caption,
              'mime': 'image/png',
            });
        if (r != 'notInstalled') return;
      } catch (_) {
        // Fall back to the share sheet.
      }
    }
    await _share(png);
  }

  Future<void> _share(Uint8List png) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png, mimeType: 'image/png', name: _fileName)],
          text: _caption,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer register')),
    body: SafeArea(
      child: FutureBuilder<Uint8List>(
        future: _png,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Could not draw the report: ${snap.error}'),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final png = snap.data!;
          return Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.memory(png, key: const Key('registerImage')),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        key: const Key('whatsappRegisterImage'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _whatsApp(png),
                        icon: const Icon(Icons.send),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        key: const Key('shareRegisterImage'),
                        onPressed: () => _share(png),
                        icon: const Icon(Icons.share),
                        label: const Text('Share…'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
