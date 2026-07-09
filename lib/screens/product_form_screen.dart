import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../utils/date_parser.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  final OcrParseResult? scanResult;

  const ProductFormScreen({super.key, this.product, this.scanResult});

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
  late final TextEditingController _notesCtrl;
  late String _category;
  late int _quantity;
  bool _saving = false;
  bool _rescanning = false;
  String? _scannedText;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final scan = widget.scanResult;
    _nameCtrl =
        TextEditingController(text: p?.name ?? scan?.productName ?? '');
    _brandCtrl =
        TextEditingController(text: p?.brand ?? scan?.brand ?? '');
    _batchCtrl =
        TextEditingController(text: p?.batch ?? scan?.batch ?? '');
    final initialExpiry = p?.expiryDate ?? scan?.expiryDate;
    _expiryCtrl = TextEditingController(
        text: initialExpiry == null ? '' : _nzDateFmt.format(initialExpiry));
    _notesCtrl = TextEditingController(text: p?.notes ?? '');
    _category = p?.category ?? scan?.category ?? 'General';
    _quantity = p?.quantity ?? 1;
    _scannedText = scan?.rawText;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _batchCtrl.dispose();
    _expiryCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim(),
        batch: _batchCtrl.text.trim(),
        category: _category,
        quantity: _quantity,
        expiryDate: expiryDate,
        addedDate: widget.product?.addedDate ?? DateTime.now(),
        notes: _notesCtrl.text.trim(),
      );
      if (_isEdit) {
        await DatabaseService.instance.update(product);
      } else {
        await DatabaseService.instance.insert(product);
      }
      await NotificationService.instance.rescheduleAll();
      if (mounted) Navigator.of(context).pop(true);
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
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Product name *',
                prefixIcon: Icon(Icons.shopping_bag_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(
                labelText: 'Brand',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _batchCtrl,
              decoration: const InputDecoration(
                labelText: 'Batch / lot number',
                prefixIcon: Icon(Icons.qr_code_2),
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
            TextFormField(
              controller: _expiryCtrl,
              decoration: InputDecoration(
                labelText: 'Expiry date *',
                hintText: 'dd/mm/yyyy',
                prefixIcon: const Icon(Icons.event),
                suffixIcon: IconButton(
                  tooltip: 'Pick from calendar',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: _pickDate,
                ),
              ),
              keyboardType: TextInputType.datetime,
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
            Row(
              children: [
                const Icon(Icons.numbers, color: Colors.grey),
                const SizedBox(width: 12),
                const Text('Quantity'),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_quantity',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes),
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
