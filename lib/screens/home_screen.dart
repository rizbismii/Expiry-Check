import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../models/store.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../utils/date_parser.dart';
import '../widgets/report_options_dialog.dart';
import 'product_form_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, expired, soon30, soon90, fresh }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _storePrefKey = 'selected_store_id';

  List<Product> _products = [];
  List<Store> _stores = [];
  int _storeId = 1;
  bool _loading = true;
  bool _scanning = false;
  _Filter _filter = _Filter.all;
  String _search = '';

  Store? get _currentStore =>
      _stores.where((s) => s.id == _storeId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.instance.requestPermissions();
  }

  Future<void> _load() async {
    final stores = await DatabaseService.instance.getStores();
    final prefs = await SharedPreferences.getInstance();
    var storeId = prefs.getInt(_storePrefKey) ?? _storeId;
    if (!stores.any((s) => s.id == storeId) && stores.isNotEmpty) {
      storeId = stores.first.id;
    }
    final products = await DatabaseService.instance.getAll(storeId: storeId);
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _storeId = storeId;
      _products = products;
      _loading = false;
    });
  }

  Future<void> _switchStore(int storeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storePrefKey, storeId);
    setState(() => _storeId = storeId);
    await _load();
  }

  List<Product> get _visible {
    var list = _products;
    switch (_filter) {
      case _Filter.expired:
        list = list.where((p) => p.isExpired).toList();
      case _Filter.soon30:
        list = list.where((p) => p.isExpiringSoon).toList();
      case _Filter.soon90:
        list = list.where((p) => p.isExpiring90).toList();
      case _Filter.fresh:
        list = list
            .where((p) => !p.isExpired && !p.isExpiringSoon && !p.isExpiring90)
            .toList();
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
        builder: (_) => ProductFormScreen(
          product: product,
          scanResult: scanResult,
          storeId: _storeId,
        ),
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
      _snack('No products in this store to export yet.');
      return;
    }
    final options = await showReportOptionsDialog(context);
    if (options == null) return;
    final filtered = options.apply(_products);
    if (filtered.isEmpty) {
      _snack('No products match the selected dates.');
      return;
    }
    try {
      await ExportService.instance.shareExcelReport(
        filtered,
        storeName: _currentStore?.name ?? 'Store',
        options: options,
      );
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
        title: _buildStoreSelector(),
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

  Widget _buildStoreSelector() {
    if (_stores.isEmpty) return const Text('Expiry Check');
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _storeId,
        isDense: true,
        dropdownColor: Theme.of(context).colorScheme.primary,
        iconEnabledColor: onPrimary,
        style: TextStyle(
          color: onPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        items: _stores
            .map((s) => DropdownMenuItem(
                  value: s.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store, size: 18, color: onPrimary),
                      const SizedBox(width: 8),
                      Text(s.name),
                    ],
                  ),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null && v != _storeId) _switchStore(v);
        },
      ),
    );
  }

  Widget _buildSummaryBar() {
    final expired = _products.where((p) => p.isExpired).length;
    final soon30 = _products.where((p) => p.isExpiringSoon).length;
    final soon90 = _products.where((p) => p.isExpiring90).length;
    final fresh = _products.length - expired - soon30 - soon90;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          _summaryChip('Expired', expired, Colors.red, _Filter.expired),
          const SizedBox(width: 6),
          _summaryChip('≤30 days', soon30, Colors.orange, _Filter.soon30),
          const SizedBox(width: 6),
          _summaryChip('≤90 days', soon90, Colors.amber, _Filter.soon90),
          const SizedBox(width: 6),
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
                ? 'No products in ${_currentStore?.name ?? 'this store'} yet.\nTap "Scan product" to add your first item.'
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
            : product.isExpiring90
                ? Colors.amber
                : Colors.green;
    final dateFmt = DateFormat('dd/MM/yyyy');
    // Brand first, then product name, matching the form and report order.
    final title = product.brand.isNotEmpty
        ? '${product.brand} — ${product.name}'
        : product.name;
    final subtitleParts = <String>[
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
                  : (product.isExpiringSoon || product.isExpiring90)
                      ? Icons.schedule
                      : Icons.check_circle_outline,
              color: color,
            ),
          ),
          title: Text(title,
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