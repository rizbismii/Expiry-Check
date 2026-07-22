import 'dart:async';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../services/sync_service.dart';

/// Always-on cloud sync status. Connecting, push and pull are automatic.
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  bool _busy = false;
  bool _canConnect = false;
  String _status = '';
  String? _lastError;
  StreamSubscription<String>? _statusSub;

  @override
  void initState() {
    super.initState();
    _load();
    _statusSub = SyncService.instance.statusStream.listen((msg) {
      if (!mounted) return;
      setState(() {
        _status = msg;
        if (msg.toLowerCase().contains('fail') ||
            msg.toLowerCase().contains('error')) {
          _lastError = msg;
        } else if (msg.toLowerCase().contains('live sync on') ||
            msg.toLowerCase().contains('listening') ||
            msg.toLowerCase().contains('always on')) {
          _lastError = null;
        }
      });
    });
  }

  Future<void> _load() async {
    final canConnect = await SyncService.instance.canConnect;
    if (!mounted) return;
    setState(() {
      _canConnect = canConnect;
      if (SyncService.instance.isSignedIn) {
        _status = 'Auto sync is on';
        _lastError = null;
      } else {
        _status = 'Connecting…';
      }
    });
  }

  Future<void> _reconnect() async {
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await SyncService.instance.setEnabled(true);
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = '$e');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = SyncService.instance.isSignedIn;
    final ready = _canConnect || SyncService.instance.hasBuiltInConfig;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auto multi-device sync',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Cloud sync stays on automatically. Phones share '
                    'inventory and staff logins — no Connect, Push or Pull.\n\n'
                    'Staff usernames stay under Manage users (not an email).\n\n'
                    'First time only: run schema_fix_userid_null.sql in the '
                    'Supabase SQL Editor, then reopen the app.',
                    style: TextStyle(height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!ready) ...[
            Card(
              margin: EdgeInsets.zero,
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'This APK does not include Supabase project settings yet.',
                  style: TextStyle(height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              live ? Icons.cloud_done : Icons.cloud_off,
              color: live ? Colors.green : Colors.grey,
            ),
            title: Text(live ? 'Auto sync on' : 'Not connected yet'),
            subtitle: Text(
              live
                  ? 'Always on — adds, edits, deletes and staff logins sync live'
                  : (_status.isNotEmpty
                      ? _status
                      : 'Waiting to connect to the shop project'),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (!live && ready) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _reconnect,
              icon: const Icon(Icons.cloud_sync),
              label: const Text('Connect now'),
            ),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _lastError!,
                  style: TextStyle(color: Colors.red.shade900, height: 1.35),
                ),
              ),
            ),
          ],
          if (_status.isNotEmpty && live) ...[
            const SizedBox(height: 16),
            Text(_status, style: TextStyle(color: Colors.grey.shade800)),
          ],
          const SizedBox(height: 24),
          Text(
            'Shop id: ${SupabaseConfig.shopId}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
