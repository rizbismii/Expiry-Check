import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../utils/date_parser.dart';
import 'product_form_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, expiringSoon, expired, fresh }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _products = [];
  bool _loading = true;
  bool _scanning = false;
  _Filter _filter = _Filter.all;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.instance.requestPermissions();
  }

  Future<void> _load() async {
    final products = await DatabaseService.instance.getAll();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  List<Product> get _visible {
    var list = _products;
    switch (_filter) {
      case _Filter.expiringSoon:
        list = list.where((p) => p.isExpiringSoon).toList();
      case _Filter.expired:
        list = list.where((p) => p.isExpired).toList();
      case _Filter.fresh:
        list = list.where((p) => !p.isExpired && !p.isExpiringSoon).toList();
      case _Filter.all:
        break;
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.brand.toLowerCase().contains(q) ||
              p.batch.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _scanWithCamera() async {
    setState(() => _scanning = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) return;
      final result = await OcrService.instance.scanImage(photo.path);
      if (!mounted) return;
      await _openForm(scanResult: result);
    } catch (e) {
      _snack('Scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openForm({Product? product, OcrParseResult? scanResult}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProductFormScreen(product: product, scanResult: scanResult),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Product product) async {
    await DatabaseService.instance.delete(product.id!);
    await NotificationService.instance.rescheduleAll();
    _load();
    _snack('${product.name} deleted');
  }

  Future<void> _exportExcel() async {
    if (_products.isEmpty) {
      _snack('No products to export yet.');
      return;
    }
    try {
      await ExportService.instance.shareExcelReport(_products);
    } catch (e) {
      _snack('Export failed: $e');
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
        title: const Text('Expiry Check'),
        actions: [
          IconButton(
            tooltip: 'Excel report',
            icon: const Icon(Icons.table_view),
            onPressed: _exportExcel,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryBar(),
                _buildSearchAndFilter(),
                Expanded(
                  child: _visible.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: _visible.length,
                            itemBuilder: (context, i) =>
                                _buildProductCard(_visible[i]),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'manual',
            tooltip: 'Add manually',
            onPressed: () => _openForm(),
            child: const Icon(Icons.edit),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: _scanning ? null : _scanWithCamera,
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(_scanning ? 'Scanning…' : 'Scan product'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final expired = _products.where((p) => p.isExpired).length;
    final soon = _products.where((p) => p.isExpiringSoon).length;
    final fresh = _products.length - expired - soon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          _summaryChip('Expired', expired, Colors.red, _Filter.expired),
          const SizedBox(width: 8),
          _summaryChip('≤ 30 days', soon, Colors.orange, _Filter.expiringSoon),
          const SizedBox(width: 8),
          _summaryChip('Fresh', fresh, Colors.green, _Filter.fresh),
        ],
      ),
    );
  }

  Widget _summaryChip(
      String label, int count, MaterialColor color, _Filter filter) {
    final selected = _filter == filter;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(
            () => _filter = selected ? _Filter.all : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.28 : 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Text('$count',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color.shade800)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Search name, brand or batch…',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => _search = v.trim()),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _products.isEmpty
                ? 'No products yet.\nTap "Scan product" to add your first item.'
                : 'Nothing matches this filter.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final MaterialColor color = product.isExpired
        ? Colors.red
        : product.isExpiringSoon
            ? Colors.orange
            : Colors.green;
    final dateFmt = DateFormat('dd/MM/yyyy');
    final subtitleParts = <String>[
      if (product.brand.isNotEmpty) product.brand,
      if (product.batch.isNotEmpty) 'Batch ${product.batch}',
      'Qty ${product.quantity}',
    ];
    return Dismissible(
      key: ValueKey(product.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete product?'),
                content: Text('Remove "${product.name}" from your inventory?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => _delete(product),
      child: Card(
        child: ListTile(
          onTap: () => _openForm(product: product),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(
              product.isExpired
                  ? Icons.error_outline
                  : product.isExpiringSoon
                      ? Icons.schedule
                      : Icons.check_circle_outline,
              color: color,
            ),
          ),
          title: Text(product.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${subtitleParts.join(' • ')}\n'
            'Expires ${dateFmt.format(product.expiryDate)}',
          ),
          isThreeLine: true,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              product.isExpired
                  ? '${-product.daysLeft}d ago'
                  : product.daysLeft == 0
                      ? 'Today'
                      : '${product.daysLeft}d left',
              style: TextStyle(
                  color: color.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}