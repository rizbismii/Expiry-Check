import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/user_service.dart';

import '../models/product.dart';
import '../models/store.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../utils/date_parser.dart';
import '../utils/nz_date_input_formatter.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  final OcrParseResult? scanResult;

  /// Store the product belongs to (for new products, the branch currently
  /// selected on the home screen).
  final int storeId;

  const ProductFormScreen({
    super.key,
    this.product,
    this.scanResult,
    this.storeId = 1,
  });

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  static final _nzDateFmt = DateFormat('dd/MM/yyyy');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _batchCtrl;
  late final TextEditingController _expiryCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late String _category;
  late int _storeId;
  List<Store> _stores = [];
  bool _saving = false;
  bool _rescanning = false;
  String? _scannedText;

  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  String? _listeningField;
  String _username = '';

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final scan = widget.scanResult;
    _storeId = p?.storeId ?? widget.storeId;
    DatabaseService.instance.getStores().then((stores) {
      if (mounted) setState(() => _stores = stores);
    });
    UserService.instance.username.then((name) {
      if (mounted && name != null) _username = name;
    });
    _nameCtrl =
        TextEditingController(text: p?.name ?? scan?.productName ?? '');
    _brandCtrl =
        TextEditingController(text: p?.brand ?? scan?.brand ?? '');
    _batchCtrl =
        TextEditingController(text: p?.batch ?? scan?.batch ?? '');
    final initialExpiry = p?.expiryDate ?? scan?.expiryDate;
    _expiryCtrl = TextEditingController(
        text: initialExpiry == null ? '' : _nzDateFmt.format(initialExpiry));
    _qtyCtrl = TextEditingController(text: '${p?.quantity ?? 1}');
    _notesCtrl = TextEditingController(text: p?.notes ?? '');
    _category = p?.category ?? scan?.category ?? 'General';
    _scannedText = scan?.rawText;
  }

  @override
  void dispose() {
    _speech.stop();
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _batchCtrl.dispose();
    _expiryCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int get _quantityValue => int.tryParse(_qtyCtrl.text.trim()) ?? 1;

  void _bumpQuantity(int delta) {
    final next = (_quantityValue + delta).clamp(1, 999999);
    setState(() => _qtyCtrl.text = '$next');
  }

  // ---- Voice input ----

  /// Starts (or stops) dictation into [controller]. For the expiry field a
  /// spoken date like "12 May 2028" or "19022027" is converted to dd/mm/yyyy.
  Future<void> _dictate(String fieldKey, TextEditingController controller,
      {bool isDate = false, bool isNumber = false}) async {
    // Tapping the mic of another field while listening: restart there.
    final wasListeningHere = _listeningField == fieldKey;
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listeningField = null);
      if (wasListeningHere) return;
    }
    if (!_speechReady) {
      // Not cached on failure so a denied permission can be retried after
      // the user grants it in system settings.
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listeningField = null);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listeningField = null);
          if (error.permanent) {
            _snack('Voice input error: ${error.errorMsg}. '
                'Check the microphone permission in system settings.');
          }
        },
      );
      if (!_speechReady) {
        _snack('Speech recognition is not available. Allow the microphone '
            'permission and make sure Google/Samsung voice input is enabled.');
        return;
      }
    }
    setState(() => _listeningField = fieldKey);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (result) {
        if (!mounted) return;
        final words = result.recognizedWords;
        if (words.isEmpty) return;
        setState(() {
          if (isDate) {
            final compact = words.replaceAll(RegExp(r'[^0-9/\-. ]'), '');
            final parsed = DateParser.parseTypedDate(compact) ??
                DateParser.parse(words).expiryDate;
            // Show raw words while partial results stream in, so the user
            // sees that the mic heard them even before a date is parsed.
            controller.text =
                parsed != null ? _nzDateFmt.format(parsed) : words;
          } else if (isNumber) {
            final digits = words.replaceAll(RegExp(r'[^0-9]'), '');
            if (digits.isNotEmpty) controller.text = digits;
          } else {
            controller.text = words;
          }
        });
      },
    );
  }

  Widget _micButton(String fieldKey, TextEditingController controller,
      {bool isDate = false, bool isNumber = false}) {
    final listening = _listeningField == fieldKey;
    return IconButton(
      tooltip: listening ? 'Stop dictation' : 'Speak',
      icon: Icon(
        listening ? Icons.mic : Icons.mic_none,
        color: listening ? Theme.of(context).colorScheme.error : null,
      ),
      onPressed: () =>
          _dictate(fieldKey, controller, isDate: isDate, isNumber: isNumber),
    );
  }

  Future<void> _rescan() async {
    setState(() => _rescanning = true);
    try {
      final photo = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 90);
      if (photo == null) return;
      final result = await OcrService.instance.scanImage(photo.path);
      if (!mounted) return;
      setState(() {
        if (result.expiryDate != null) {
          _expiryCtrl.text = _nzDateFmt.format(result.expiryDate!);
        }
        if (result.batch != null && _batchCtrl.text.isEmpty) {
          _batchCtrl.text = result.batch!;
        }
        if (result.brand != null && _brandCtrl.text.isEmpty) {
          _brandCtrl.text = result.brand!;
        }
        if (result.productName != null && _nameCtrl.text.isEmpty) {
          _nameCtrl.text = result.productName!;
        }
        if (result.category != null) _category = result.category!;
        _scannedText = result.rawText;
      });
      final found = [
        if (result.productName != null) 'product',
        if (result.brand != null) 'brand',
        if (result.expiryDate != null) 'expiry date',
        if (result.batch != null) 'batch',
        if (result.category != null) 'category',
      ];
      _snack(found.isEmpty
          ? 'No details recognized — try a closer, well-lit photo.'
          : 'Recognized: ${found.join(', ')}');
    } catch (e) {
      _snack('Scan failed: $e');
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = DateParser.parseTypedDate(_expiryCtrl.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
      helpText: 'Select expiry date',
    );
    if (picked != null) {
      setState(() => _expiryCtrl.text = _nzDateFmt.format(picked));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final expiryDate = DateParser.parseTypedDate(_expiryCtrl.text);
    if (expiryDate == null) {
      _snack('Please enter a valid expiry date (dd/mm/yyyy).');
      return;
    }
    setState(() => _saving = true);
    try {
      final product = Product(
        id: widget.product?.id,
        storeId: _storeId,
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim(),
        batch: _batchCtrl.text.trim(),
        category: _category,
        quantity: _quantityValue,
        expiryDate: expiryDate,
        addedDate: widget.product?.addedDate ?? DateTime.now(),
        notes: _notesCtrl.text.trim(),
        createdBy: widget.product?.createdBy.isNotEmpty == true
            ? widget.product!.createdBy
            : _username,
      );
      String? mergeMessage;
      if (_isEdit) {
        await DatabaseService.instance.update(product);
      } else {
        // Same brand + product + batch + expiry in this store: offer to top
        // up the existing entry's quantity instead of adding a duplicate row.
        final existing = await DatabaseService.instance.findMatching(product);
        if (existing != null) {
          if (!mounted) return;
          final increase = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Already in the list'),
              content: Text(
                  '"${existing.brand.isNotEmpty ? '${existing.brand} — ' : ''}'
                  '${existing.name}" with the same batch and expiry date '
                  'already has quantity ${existing.quantity}.\n\n'
                  'Increase it to ${existing.quantity + product.quantity} '
                  'instead of adding a new line?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Add as new line')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Increase quantity')),
              ],
            ),
          );
          if (increase == null) {
            // Dialog dismissed: stay on the form without saving.
            setState(() => _saving = false);
            return;
          }
          if (increase) {
            final merged = existing.copyWith(
                quantity: existing.quantity + product.quantity);
            await DatabaseService.instance.update(merged);
            mergeMessage =
                'Quantity of "${existing.name}" increased to ${merged.quantity}.';
          } else {
            await DatabaseService.instance.insert(product);
          }
        } else {
          await DatabaseService.instance.insert(product);
        }
      }
      await NotificationService.instance.rescheduleAll();
      if (mounted) {
        if (mergeMessage != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(mergeMessage)));
        }
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _snack('Save failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit product' : 'Add product'),
        actions: [
          IconButton(
            tooltip: 'Scan with camera',
            icon: _rescanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt),
            onPressed: _rescanning ? null : _rescan,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.scanResult != null && !_isEdit) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _scanSummary(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_stores.isNotEmpty) ...[
              DropdownButtonFormField<int>(
                value: _stores.any((s) => s.id == _storeId)
                    ? _storeId
                    : _stores.first.id,
                decoration: const InputDecoration(
                  labelText: 'Store branch',
                  prefixIcon: Icon(Icons.store),
                ),
                items: _stores
                    .map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() => _storeId = v ?? _storeId),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _brandCtrl,
              decoration: InputDecoration(
                labelText: 'Brand name',
                prefixIcon: const Icon(Icons.sell_outlined),
                suffixIcon: _micButton('brand', _brandCtrl),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Product name *',
                prefixIcon: const Icon(Icons.shopping_bag_outlined),
                suffixIcon: _micButton('name', _nameCtrl),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _expiryCtrl,
              decoration: InputDecoration(
                labelText: 'Expiry date *',
                hintText: 'dd/mm/yyyy — type digits, slashes are added',
                prefixIcon: const Icon(Icons.event),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _micButton('expiry', _expiryCtrl, isDate: true),
                    IconButton(
                      tooltip: 'Pick from calendar',
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _pickDate,
                    ),
                  ],
                ),
              ),
              // Numeric keyboard + auto-inserted slashes: some Android
              // keyboards hide '/' on the datetime layout, which made the
              // field impossible to type into.
              keyboardType: TextInputType.number,
              inputFormatters: [NzDateInputFormatter()],
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Expiry date is required';
                }
                if (DateParser.parseTypedDate(v) == null) {
                  return 'Enter a valid date as dd/mm/yyyy';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _batchCtrl,
              decoration: InputDecoration(
                labelText: 'Batch / lot number',
                prefixIcon: const Icon(Icons.qr_code_2),
                suffixIcon: _micButton('batch', _batchCtrl),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: {..._categoryOptions()}
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'General'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Quantity *',
                      prefixIcon: const Icon(Icons.numbers),
                      suffixIcon: _micButton('qty', _qtyCtrl, isNumber: true),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    // Refreshes the enabled state of the − button.
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 1) {
                        return 'Enter a quantity of 1 or more';
                      }
                      return null;
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Decrease',
                  onPressed:
                      _quantityValue > 1 ? () => _bumpQuantity(-1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'Increase',
                  onPressed: () => _bumpQuantity(1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Notes',
                prefixIcon: const Icon(Icons.notes),
                suffixIcon: _micButton('notes', _notesCtrl),
              ),
              maxLines: 3,
            ),
            if (_scannedText != null && _scannedText!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Recognized text (from camera)'),
                tilePadding: EdgeInsets.zero,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade100,
                    child: Text(_scannedText!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving
                  ? 'Saving…'
                  : _isEdit
                      ? 'Update product'
                      : 'Save product'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }

  /// Category list plus the product's saved category, so items saved before
  /// a category rename still render in the dropdown.
  List<String> _categoryOptions() =>
      {...Product.categories, _category}.toList();

  String _scanSummary() {
    final scan = widget.scanResult!;
    final found = <String>[
      if (scan.productName != null) 'product name',
      if (scan.brand != null) 'brand',
      if (scan.expiryDate != null) 'expiry date',
      if (scan.batch != null) 'batch number',
      if (scan.category != null) 'category',
    ];
    return found.isEmpty
        ? 'Scan complete, but no details were recognized. Fill the form manually or rescan with the camera button above.'
        : 'AI scan pre-filled: ${found.join(', ')}. Review and correct before saving.';
  }
}
