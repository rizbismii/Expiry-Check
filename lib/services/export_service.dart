import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../models/store.dart';
import 'database_service.dart' show DeletionEntry;

class BackupData {
  final List<Product> products;
  final List<Store> stores;

  const BackupData({required this.products, this.stores = const []});
}

enum ReportBasis { all, expiryDate, addedDate }

/// User-selected report settings: which date the report is based on and an
/// optional inclusive date range.
class ReportOptions {
  final ReportBasis basis;
  final DateTime? from;
  final DateTime? to;

  const ReportOptions({
    this.basis = ReportBasis.expiryDate,
    this.from,
    this.to,
  });

  String get basisLabel => switch (basis) {
        ReportBasis.all => 'All products',
        ReportBasis.expiryDate => 'Expiry date',
        ReportBasis.addedDate => 'Added date',
      };

  DateTime _basisDate(Product p) {
    final d = basis == ReportBasis.addedDate ? p.addedDate : p.expiryDate;
    return DateTime(d.year, d.month, d.day);
  }

  List<Product> apply(List<Product> products) {
    final filtered = basis == ReportBasis.all
        ? [...products]
        : products.where((p) {
            final day = _basisDate(p);
            if (from != null && day.isBefore(from!)) return false;
            if (to != null && day.isAfter(to!)) return false;
            return true;
          }).toList();
    return filtered
      ..sort((a, b) => _basisDate(a).compareTo(_basisDate(b)));
  }

  String rangeLabel(DateFormat fmt) {
    if (basis == ReportBasis.all || (from == null && to == null)) {
      return 'All dates';
    }
    final start = from != null ? fmt.format(from!) : 'Start';
    final end = to != null ? fmt.format(to!) : 'Today onwards';
    return '$start – $end';
  }
}

/// Generates Excel reports and JSON backups. Files are saved to local app
/// storage and offered via the system share sheet, so users can send them to
/// Google Drive / iCloud / email at zero infrastructure cost.
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  // NZ date format for report columns.
  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _stampFmt = DateFormat('yyyyMMdd_HHmmss');

  /// When [storeNames] is provided (the "All stores" report), a Store column
  /// is added so rows from different branches stay distinguishable.
  /// [deletionLog] adds a "Deletion Log" audit sheet; [generatedBy] appears
  /// in the summary.
  Future<File> buildExcelReport(List<Product> products,
      {required String storeName,
      ReportOptions options = const ReportOptions(),
      Map<int, String>? storeNames,
      List<DeletionEntry> deletionLog = const [],
      String generatedBy = ''}) async {
    final excel = Excel.createExcel();
    // Excel sheet names are limited to 31 chars and a restricted charset.
    final cleaned =
        storeName.replaceAll(RegExp(r'[\[\]\*\?:\/\\]'), ' ').trim();
    final sheetName = cleaned.isEmpty ? 'Inventory' : cleaned;
    final safeSheetName =
        sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName;
    final sheet = excel[safeSheetName];
    excel.setDefaultSheet(safeSheetName);
    excel.delete('Sheet1');

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1B5E20'),
      fontColorHex: ExcelColor.white,
    );
    final headers = [
      if (storeNames != null) 'Store',
      'Brand Name',
      'Product Name',
      'Barcode ID',
      'Prod Date',
      'Expiry Date',
      'Batch / Lot No.',
      'Category',
      'Quantity',
      'Days Left',
      'Status',
      'Added On',
      'Created By',
      'Notes',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    final sorted = options.apply(products);
    for (var r = 0; r < sorted.length; r++) {
      final p = sorted[r];
      final row = <CellValue>[
        if (storeNames != null)
          TextCellValue(storeNames[p.storeId] ?? 'Store ${p.storeId}'),
        TextCellValue(p.brand),
        TextCellValue(p.name),
        TextCellValue(p.barcodeId),
        TextCellValue(
            p.prodDate == null ? '' : _dateFmt.format(p.prodDate!)),
        TextCellValue(_dateFmt.format(p.expiryDate)),
        TextCellValue(p.batch),
        TextCellValue(p.category),
        IntCellValue(p.quantity),
        IntCellValue(p.daysLeft),
        TextCellValue(p.statusLabel),
        TextCellValue(_dateFmt.format(p.addedDate)),
        TextCellValue(p.createdBy),
        TextCellValue(p.notes),
      ];
      for (var c = 0; c < row.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = row[c];
      }
    }

    // Summary sheet.
    final summary = excel['Summary'];
    final expired = sorted.where((p) => p.isExpired).length;
    final soon = sorted.where((p) => p.isExpiringSoon).length;
    final ninety = sorted.where((p) => p.isExpiring90).length;
    final rows = <List<CellValue>>[
      [TextCellValue('Store branch'), TextCellValue(storeName)],
      if (generatedBy.isNotEmpty)
        [TextCellValue('Generated by'), TextCellValue(generatedBy)],
      [TextCellValue('Report based on'), TextCellValue(options.basisLabel)],
      [TextCellValue('Date range'),
        TextCellValue(options.rangeLabel(_dateFmt))],
      [TextCellValue('Report generated'),
        TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()))],
      [TextCellValue('Total products'), IntCellValue(sorted.length)],
      [TextCellValue('Expired'), IntCellValue(expired)],
      [TextCellValue('Expiring within 30 days'), IntCellValue(soon)],
      [TextCellValue('Expiring within 31-90 days'), IntCellValue(ninety)],
      [
        TextCellValue('Fresh'),
        IntCellValue(sorted.length - expired - soon - ninety),
      ],
    ];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        summary
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value = rows[r][c];
      }
    }

    // Audit sheet listing rows deleted via swipe, with the required note.
    if (deletionLog.isNotEmpty) {
      final logSheet = excel['Deletion Log'];
      final logHeaders = [
        'Deleted On',
        'Deleted By',
        'Reason / Note',
        'Store',
        'Brand Name',
        'Product Name',
        'Batch / Lot No.',
        'Expiry Date',
        'Quantity',
      ];
      for (var c = 0; c < logHeaders.length; c++) {
        final cell = logSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(logHeaders[c]);
        cell.cellStyle = headerStyle;
      }
      for (var r = 0; r < deletionLog.length; r++) {
        final e = deletionLog[r];
        final row = <CellValue>[
          TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(e.deletedAt)),
          TextCellValue(e.deletedBy),
          TextCellValue(e.note),
          TextCellValue(storeNames?[e.storeId] ?? storeName),
          TextCellValue(e.brand),
          TextCellValue(e.name),
          TextCellValue(e.batch),
          TextCellValue(_dateFmt.format(e.expiryDate)),
          IntCellValue(e.quantity),
        ];
        for (var c = 0; c < row.length; c++) {
          logSheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: c, rowIndex: r + 1))
              .value = row[c];
        }
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final slug = _slugify(storeName);
    final file = File(
        '${dir.path}/expiry_report_${slug}_${_stampFmt.format(DateTime.now())}.xlsx');
    await file.writeAsBytes(excel.encode()!, flush: true);
    return file;
  }

  Future<void> shareExcelReport(List<Product> products,
      {required String storeName,
      ReportOptions options = const ReportOptions(),
      Map<int, String>? storeNames,
      List<DeletionEntry> deletionLog = const [],
      String generatedBy = ''}) async {
    final file = await buildExcelReport(products,
        storeName: storeName,
        options: options,
        storeNames: storeNames,
        deletionLog: deletionLog,
        generatedBy: generatedBy);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: 'Expiry Check report — $storeName (${options.basisLabel})',
      text: 'Inventory report for $storeName generated by Expiry Check.',
    ));
  }

  Future<File> buildJsonBackup(
      List<Product> products, List<Store> stores) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/expiry_backup_${_stampFmt.format(DateTime.now())}.json');
    final payload = {
      'app': 'expiry_check',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'stores': stores.map((s) => s.toMap()).toList(),
      'products': products.map((p) => p.toMap()..remove('id')).toList(),
    };
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true);
    return file;
  }

  Future<void> shareJsonBackup(
      List<Product> products, List<Store> stores) async {
    final file = await buildJsonBackup(products, stores);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: 'Expiry Check backup',
      text: 'Backup file — keep it in your cloud drive to restore later.',
    ));
  }

  BackupData parseBackup(String jsonString) {
    final decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'expiry_check') {
      throw const FormatException('Not a valid Expiry Check backup file.');
    }
    final items = decoded['products'] as List<dynamic>;
    final products = items
        .map((e) => Product.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    // Version 1 backups had no store list; products default to store 1.
    final storeItems = decoded['stores'] as List<dynamic>? ?? const [];
    final stores = storeItems
        .map((e) => Store.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return BackupData(products: products, stores: stores);
  }

  static String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'store' : slug;
  }
}
