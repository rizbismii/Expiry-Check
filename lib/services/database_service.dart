import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/product.dart';
import '../models/store.dart';

/// Audit record kept when a product row is deleted via swipe.
class DeletionEntry {
  final DateTime deletedAt;
  final String deletedBy;
  final String note;
  final int storeId;
  final String name;
  final String brand;
  final String batch;
  final DateTime expiryDate;
  final int quantity;

  const DeletionEntry({
    required this.deletedAt,
    this.deletedBy = '',
    this.note = '',
    this.storeId = 1,
    required this.name,
    this.brand = '',
    this.batch = '',
    required this.expiryDate,
    this.quantity = 1,
  });

  factory DeletionEntry.fromMap(Map<String, dynamic> map) => DeletionEntry(
        deletedAt: DateTime.parse(map['deletedAt'] as String),
        deletedBy: map['deletedBy'] as String? ?? '',
        note: map['note'] as String? ?? '',
        storeId: map['storeId'] as int? ?? 1,
        name: map['name'] as String? ?? '',
        brand: map['brand'] as String? ?? '',
        batch: map['batch'] as String? ?? '',
        expiryDate: DateTime.parse(map['expiryDate'] as String),
        quantity: map['quantity'] as int? ?? 1,
      );
}

/// Local-first SQLite storage. Keeping data on-device is free (no server
/// costs); users can back up/restore via the exported JSON/Excel files in
/// Settings, using any cloud drive they already have (Google Drive, iCloud).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const _dbName = 'expiry_check.db';
  static const _dbVersion = 5;
  static const _table = 'products';
  static const _storesTable = 'stores';
  static const _deletionsTable = 'deletion_log';
  static const _usersTable = 'users';

  /// Admin may create at most this many staff accounts.
  static const maxUsers = 10;

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
            barcodeId TEXT NOT NULL DEFAULT '',
            batch TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'General',
            quantity INTEGER NOT NULL DEFAULT 1,
            prodDate TEXT,
            expiryDate TEXT NOT NULL,
            addedDate TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT '',
            createdBy TEXT NOT NULL DEFAULT ''
          )
        ''');
        await _createStoresTable(db);
        await _createDeletionsTable(db);
        await _createUsersTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN storeId INTEGER NOT NULL DEFAULT 1');
          await _createStoresTable(db);
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE $_table ADD COLUMN createdBy TEXT NOT NULL DEFAULT ''");
          await _createDeletionsTable(db);
        }
        if (oldVersion < 4) {
          await _createUsersTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
              "ALTER TABLE $_table ADD COLUMN barcodeId TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE $_table ADD COLUMN prodDate TEXT');
        }
      },
    );
  }

  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_usersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createDeletionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_deletionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deletedAt TEXT NOT NULL,
        deletedBy TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        storeId INTEGER NOT NULL DEFAULT 1,
        name TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT '',
        batch TEXT NOT NULL DEFAULT '',
        expiryDate TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1
      )
    ''');
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

  // ---- Users (admin-managed staff accounts) ----

  Future<List<AppUser>> getUsers() async {
    final db = await database;
    final rows = await db.query(_usersTable, orderBy: 'username ASC');
    return rows.map(AppUser.fromMap).toList();
  }

  /// Adds a staff user. Returns null on success, or an error message.
  Future<String?> addUser(String username, String password) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_usersTable')) ??
        0;
    if (count >= maxUsers) {
      return 'User limit reached ($maxUsers). Delete a user first.';
    }
    try {
      await db.insert(_usersTable, {
        'username': username.trim(),
        'password': password,
      });
      return null;
    } on DatabaseException {
      return 'Username "$username" already exists.';
    }
  }

  Future<void> updateUserPassword(int id, String password) async {
    final db = await database;
    await db.update(_usersTable, {'password': password},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteUser(int id) async {
    final db = await database;
    await db.delete(_usersTable, where: 'id = ?', whereArgs: [id]);
  }

  /// Looks up a staff user by credentials; null when they don't match.
  Future<AppUser?> findUser(String username, String password) async {
    final db = await database;
    final rows = await db.query(
      _usersTable,
      where: 'username = ? COLLATE NOCASE AND password = ?',
      whereArgs: [username.trim(), password],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  /// Distinct brand names already in the inventory, used to auto-correct
  /// OCR misreads against products the shop actually stocks.
  Future<List<String>> getKnownBrands() async {
    final db = await database;
    final rows = await db.rawQuery(
        "SELECT DISTINCT brand FROM $_table WHERE brand != '' ");
    return rows.map((r) => r['brand'] as String).toList();
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

  /// Normalization used for duplicate detection: lowercase with everything
  /// except letters and digits stripped, so "ALY32 260513", "a l y 32260513"
  /// and "Al y 32 260513" (typical OCR/voice spacing noise) all match.
  static String normalizeForMatch(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Key identifying duplicate rows: store + brand + name + batch +
  /// category + expiry day, all normalized.
  static String duplicateKey(Product p) => [
        p.storeId,
        normalizeForMatch(p.name),
        normalizeForMatch(p.brand),
        normalizeForMatch(p.batch),
        normalizeForMatch(p.category),
        '${p.expiryDate.year}-${p.expiryDate.month}-${p.expiryDate.day}',
      ].join('|');

  /// Finds an existing product in the same store with the same brand, name,
  /// batch, category and expiry date, used to merge duplicates by increasing
  /// quantity instead of adding a second row. Comparison is done in Dart so
  /// casing, spacing and stored date-time noise never break the match.
  Future<Product?> findMatching(Product p) async {
    final candidates = await getAll(storeId: p.storeId);
    final key = duplicateKey(p);
    for (final e in candidates) {
      if (e.id != null && e.id == p.id) continue; // never merge into itself
      if (duplicateKey(e) == key && _sameDay(e.expiryDate, p.expiryDate)) {
        return e;
      }
    }
    return null;
  }

  Future<List<Product>> getExpiringWithin(int days) async {
    final all = await getAll();
    return all.where((p) => p.daysLeft <= days).toList();
  }

  /// Merges rows that are duplicates of each other (same store, brand, name,
  /// batch and expiry day after normalization) by summing quantities.
  /// Returns the number of rows removed.
  Future<int> mergeDuplicates() async {
    final all = await getAll();
    final byKey = <String, Product>{};
    var removed = 0;
    for (final p in all) {
      final key = duplicateKey(p);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = p;
      } else {
        final merged =
            existing.copyWith(quantity: existing.quantity + p.quantity);
        await update(merged);
        await delete(p.id!);
        byKey[key] = merged;
        removed++;
      }
    }
    return removed;
  }

  // ---- Deletion log ----

  Future<void> logDeletion(Product p,
      {required String note, required String deletedBy}) async {
    final db = await database;
    await db.insert(_deletionsTable, {
      'deletedAt': DateTime.now().toIso8601String(),
      'deletedBy': deletedBy,
      'note': note,
      'storeId': p.storeId,
      'name': p.name,
      'brand': p.brand,
      'batch': p.batch,
      'expiryDate': p.expiryDate.toIso8601String(),
      'quantity': p.quantity,
    });
  }

  Future<List<DeletionEntry>> getDeletionLog({int? storeId}) async {
    final db = await database;
    final rows = await db.query(
      _deletionsTable,
      where: storeId != null ? 'storeId = ?' : null,
      whereArgs: storeId != null ? [storeId] : null,
      orderBy: 'deletedAt DESC',
    );
    return rows.map(DeletionEntry.fromMap).toList();
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
