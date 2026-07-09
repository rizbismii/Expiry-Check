import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../models/store.dart';

/// Local-first SQLite storage. Keeping data on-device is free (no server
/// costs); users can back up/restore via the exported JSON/Excel files in
/// Settings, using any cloud drive they already have (Google Drive, iCloud).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const _dbName = 'expiry_check.db';
  static const _dbVersion = 2;
  static const _table = 'products';
  static const _storesTable = 'stores';

  static const defaultStoreNames = ['Main Store', 'Branch 2', 'Branch 3'];

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      join(dir, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            storeId INTEGER NOT NULL DEFAULT 1,
            name TEXT NOT NULL,
            brand TEXT NOT NULL DEFAULT '',
            batch TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'General',
            quantity INTEGER NOT NULL DEFAULT 1,
            expiryDate TEXT NOT NULL,
            addedDate TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT ''
          )
        ''');
        await _createStoresTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN storeId INTEGER NOT NULL DEFAULT 1');
          await _createStoresTable(db);
        }
      },
    );
  }

  Future<void> _createStoresTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_storesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
    for (final name in defaultStoreNames) {
      await db.insert(_storesTable, {'name': name});
    }
  }

  // ---- Stores ----

  Future<List<Store>> getStores() async {
    final db = await database;
    final rows = await db.query(_storesTable, orderBy: 'id ASC');
    return rows.map(Store.fromMap).toList();
  }

  Future<void> renameStore(int id, String name) async {
    final db = await database;
    await db.update(
      _storesTable,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- Products ----

  Future<Product> insert(Product product) async {
    final db = await database;
    final map = product.toMap()..remove('id');
    final id = await db.insert(_table, map);
    return product.copyWith(id: id);
  }

  Future<void> update(Product product) async {
    final db = await database;
    await db.update(
      _table,
      product.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// All products, or only one branch's inventory when [storeId] is given.
  Future<List<Product>> getAll({int? storeId}) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: storeId != null ? 'storeId = ?' : null,
      whereArgs: storeId != null ? [storeId] : null,
      orderBy: 'expiryDate ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Normalization used for duplicate detection: case-insensitive, ignores
  /// leading/trailing/repeated whitespace (OCR and typing often differ there).
  static String normalizeForMatch(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Finds an existing product in the same store with the same brand, name,
  /// batch and expiry date, used to merge duplicates by increasing quantity
  /// instead of adding a second row. Comparison is done in Dart so casing,
  /// extra spaces and stored date-time noise never break the match.
  Future<Product?> findMatching(Product p) async {
    final candidates = await getAll(storeId: p.storeId);
    final name = normalizeForMatch(p.name);
    final brand = normalizeForMatch(p.brand);
    final batch = normalizeForMatch(p.batch);
    for (final e in candidates) {
      if (e.id != null && e.id == p.id) continue; // never merge into itself
      if (normalizeForMatch(e.name) == name &&
          normalizeForMatch(e.brand) == brand &&
          normalizeForMatch(e.batch) == batch &&
          _sameDay(e.expiryDate, p.expiryDate)) {
        return e;
      }
    }
    return null;
  }

  Future<List<Product>> getExpiringWithin(int days) async {
    final all = await getAll();
    return all.where((p) => p.daysLeft <= days).toList();
  }

  /// Replaces the whole inventory (used by backup restore). When [stores]
  /// is provided, matching store ids are renamed to the backed-up names.
  Future<void> replaceAll(List<Product> products, {List<Store>? stores}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(_table);
      for (final p in products) {
        await txn.insert(_table, p.toMap()..remove('id'));
      }
      if (stores != null) {
        for (final s in stores) {
          await txn.update(
            _storesTable,
            {'name': s.name},
            where: 'id = ?',
            whereArgs: [s.id],
          );
        }
      }
    });
  }
}
