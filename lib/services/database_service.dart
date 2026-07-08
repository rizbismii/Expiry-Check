import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

/// Local-first SQLite storage. Keeping data on-device is free (no server
/// costs); users can back up/restore via the exported JSON/Excel files in
/// Settings, using any cloud drive they already have (Google Drive, iCloud).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const _dbName = 'expiry_check.db';
  static const _table = 'products';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      join(dir, _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
      },
    );
  }

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

  Future<List<Product>> getAll() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'expiryDate ASC');
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> getExpiringWithin(int days) async {
    final all = await getAll();
    return all.where((p) => p.daysLeft <= days).toList();
  }

  Future<void> replaceAll(List<Product> products) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(_table);
      for (final p in products) {
        await txn.insert(_table, p.toMap()..remove('id'));
      }
    });
  }
}
