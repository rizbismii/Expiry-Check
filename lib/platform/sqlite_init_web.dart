import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Registers the wasm SQLite factory used by [DatabaseService] in browsers.
Future<void> initSqliteForPlatform() async {
  databaseFactory = databaseFactoryFfiWeb;
}
