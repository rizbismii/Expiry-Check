import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/store.dart';
import 'database_service.dart';

/// Live multi-device sync via Supabase.
///
/// Model: one shared shop sync account (email/password). Every device signs
/// into the same account; RLS scopes rows to that auth user. Local SQLite
/// stays the offline cache; writes upsert to the cloud and Realtime pulls
/// remote changes back in.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _prefUrl = 'supabase_url';
  static const _prefAnonKey = 'supabase_anon_key';
  static const _prefEnabled = 'supabase_sync_enabled';

  static const _uuid = Uuid();

  bool _initialized = false;
  bool _applyingRemote = false;
  RealtimeChannel? _channel;
  final _status = StreamController<String>.broadcast();

  Stream<String> get statusStream => _status.stream;

  bool get isConfigured =>
      _initialized && Supabase.instance.isInitialized;

  bool get isSignedIn =>
      isConfigured && Supabase.instance.client.auth.currentUser != null;

  String? get syncEmail =>
      Supabase.instance.client.auth.currentUser?.email;

  /// Call once at app start after [WidgetsFlutterBinding.ensureInitialized].
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefEnabled) ?? false;
    final url = prefs.getString(_prefUrl)?.trim() ?? '';
    final key = prefs.getString(_prefAnonKey)?.trim() ?? '';
    if (!enabled || url.isEmpty || key.isEmpty) {
      _initialized = false;
      return;
    }
    await _initClient(url, key);
    if (isSignedIn) {
      await startRealtime();
      unawaited(pullAll());
    }
  }

  Future<void> _initClient(String url, String publishableKey) async {
    if (Supabase.instance.isInitialized) {
      // Already initialized for this process — update prefs only.
      _initialized = true;
      return;
    }
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    _initialized = true;
  }

  Future<void> saveConfig({
    required String url,
    required String anonKey,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUrl, url.trim());
    await prefs.setString(_prefAnonKey, anonKey.trim());
    await prefs.setBool(_prefEnabled, enabled);
    if (enabled && url.trim().isNotEmpty && anonKey.trim().isNotEmpty) {
      await _initClient(url.trim(), anonKey.trim());
    } else {
      await stopRealtime();
      _initialized = false;
    }
  }

  Future<(String, String, bool)> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getString(_prefUrl) ?? '',
      prefs.getString(_prefAnonKey) ?? '',
      prefs.getBool(_prefEnabled) ?? false,
    );
  }

  Future<void> signUp(String email, String password) async {
    _ensureReady();
    final res = await Supabase.instance.client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    if (res.user == null) {
      throw Exception('Sign-up failed. Check the email confirmation setting '
          'in your Supabase project (Auth → Providers → Email).');
    }
    _emit('Signed up as ${email.trim()}');
    await pushAll();
    await startRealtime();
  }

  Future<void> signIn(String email, String password) async {
    _ensureReady();
    await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _emit('Signed in as ${email.trim()}');
    await pullAll();
    await pushAll();
    await startRealtime();
  }

  Future<void> signOutSync() async {
    await stopRealtime();
    if (isConfigured) {
      await Supabase.instance.client.auth.signOut();
    }
    _emit('Cloud sync signed out');
  }

  void _ensureReady() {
    if (!isConfigured) {
      throw Exception('Enter your Supabase URL and anon key first.');
    }
  }

  String ensureCloudId(String? existing) {
    if (existing != null && existing.isNotEmpty) return existing;
    return _uuid.v4();
  }

  /// Upsert one product after a local write.
  Future<void> upsertProduct(Product product) async {
    if (!isSignedIn || _applyingRemote) return;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final toSend =
        await DatabaseService.instance.ensurePersistedCloudId(product);
    await Supabase.instance.client
        .from('products')
        .upsert(toSend.toRemoteMap(userId));
  }

  /// Soft-delete on the server so other devices drop the row.
  Future<void> deleteProduct(Product product) async {
    if (!isSignedIn || _applyingRemote) return;
    final cloudId = product.cloudId;
    if (cloudId.isEmpty) return;
    await Supabase.instance.client.from('products').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', cloudId);
  }

  Future<void> upsertStore(Store store) async {
    if (!isSignedIn || _applyingRemote) return;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client.from('stores').upsert({
      'user_id': userId,
      'store_id': store.id,
      'name': store.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> pushDeletion(DeletionEntry entry) async {
    if (!isSignedIn || _applyingRemote) return;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client.from('deletion_log').insert({
      'user_id': userId,
      'deleted_at': entry.deletedAt.toUtc().toIso8601String(),
      'deleted_by': entry.deletedBy,
      'note': entry.note,
      'store_id': entry.storeId,
      'name': entry.name,
      'brand': entry.brand,
      'batch': entry.batch,
      'expiry_date': entry.expiryDate.toUtc().toIso8601String(),
      'quantity': entry.quantity,
    });
  }

  /// Full push of local inventory + store names.
  Future<void> pushAll() async {
    if (!isSignedIn) return;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final products = await DatabaseService.instance.getAll();
    final stores = await DatabaseService.instance.getStores();

    for (final s in stores) {
      await Supabase.instance.client.from('stores').upsert({
        'user_id': userId,
        'store_id': s.id,
        'name': s.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    if (products.isEmpty) {
      _emit('Pushed stores (no products yet)');
      return;
    }

    // Ensure every local row has a cloudId before upsert.
    final payload = <Map<String, dynamic>>[];
    for (var p in products) {
      if (p.cloudId.isEmpty) {
        p = p.copyWith(cloudId: _uuid.v4(), updatedAt: DateTime.now());
        await DatabaseService.instance.update(p, sync: false);
      }
      payload.add(p.toRemoteMap(userId));
    }
    await Supabase.instance.client.from('products').upsert(payload);
    _emit('Pushed ${payload.length} product(s)');
  }

  /// Pull remote rows into SQLite (last-write-wins on [updatedAt]).
  Future<void> pullAll() async {
    if (!isSignedIn) return;
    _applyingRemote = true;
    try {
      final client = Supabase.instance.client;

      final storeRows = await client.from('stores').select();
      for (final row in storeRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['store_id'] as int?;
        final name = map['name'] as String? ?? '';
        if (id != null && name.isNotEmpty) {
          await DatabaseService.instance.renameStore(id, name, sync: false);
        }
      }

      final rows =
          await client.from('products').select().isFilter('deleted_at', null);
      var applied = 0;
      for (final row in rows as List) {
        final remote =
            Product.fromRemoteMap(Map<String, dynamic>.from(row as Map));
        if (remote.cloudId.isEmpty) continue;
        await DatabaseService.instance.applyRemoteProduct(remote);
        applied++;
      }

      // Soft-deleted remotes → remove local copies.
      final deleted = await client
          .from('products')
          .select('id')
          .not('deleted_at', 'is', null);
      for (final row in deleted as List) {
        final id = (row as Map)['id'] as String?;
        if (id != null) {
          await DatabaseService.instance.deleteByCloudId(id, sync: false);
        }
      }

      final deletionRows = await client.from('deletion_log').select();
      var deletions = 0;
      for (final row in deletionRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final entry = DeletionEntry(
          deletedAt: DateTime.parse(map['deleted_at'] as String).toLocal(),
          deletedBy: map['deleted_by'] as String? ?? '',
          note: map['note'] as String? ?? '',
          storeId: map['store_id'] as int? ?? 1,
          name: map['name'] as String? ?? '',
          brand: map['brand'] as String? ?? '',
          batch: map['batch'] as String? ?? '',
          expiryDate: DateTime.parse(map['expiry_date'] as String).toLocal(),
          quantity: map['quantity'] as int? ?? 1,
        );
        final added =
            await DatabaseService.instance.applyRemoteDeletion(entry);
        if (added) deletions++;
      }

      _emit('Pulled $applied product(s)'
          '${deletions > 0 ? ', $deletions deletion(s)' : ''}');
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> startRealtime() async {
    if (!isSignedIn) return;
    await stopRealtime();
    final client = Supabase.instance.client;
    _channel = client
        .channel('products-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            unawaited(_onRemoteChange(payload));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stores',
          callback: (payload) {
            unawaited(_onRemoteStoreChange(payload));
          },
        )
        .subscribe();
    _emit('Live sync listening');
  }

  Future<void> stopRealtime() async {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      await Supabase.instance.client.removeChannel(ch);
    }
  }

  Future<void> _onRemoteChange(PostgresChangePayload payload) async {
    if (_applyingRemote) return;
    _applyingRemote = true;
    try {
      final event = payload.eventType;
      if (event == PostgresChangeEvent.delete) {
        final id = payload.oldRecord['id'] as String?;
        if (id != null) {
          await DatabaseService.instance.deleteByCloudId(id, sync: false);
        }
        _emit('Synced change from another device');
        return;
      }
      final record = payload.newRecord;
      if (record.isEmpty) return;
      if (record['deleted_at'] != null) {
        final id = record['id'] as String?;
        if (id != null) {
          await DatabaseService.instance.deleteByCloudId(id, sync: false);
        }
        _emit('Synced change from another device');
        return;
      }
      final remote = Product.fromRemoteMap(record);
      await DatabaseService.instance.applyRemoteProduct(remote);
      _emit('Synced change from another device');
    } catch (e) {
      _emit('Sync apply failed: $e');
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _onRemoteStoreChange(PostgresChangePayload payload) async {
    if (_applyingRemote) return;
    final record = payload.newRecord;
    if (record.isEmpty) return;
    final id = record['store_id'] as int?;
    final name = record['name'] as String? ?? '';
    if (id == null || name.isEmpty) return;
    _applyingRemote = true;
    try {
      await DatabaseService.instance.renameStore(id, name, sync: false);
      _emit('Synced change from another device');
    } catch (e) {
      _emit('Sync apply failed: $e');
    } finally {
      _applyingRemote = false;
    }
  }

  void _emit(String message) {
    if (!_status.isClosed) _status.add(message);
  }
}
