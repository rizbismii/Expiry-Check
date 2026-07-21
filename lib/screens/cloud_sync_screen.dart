import 'dart:async';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../services/sync_service.dart';

/// Simple on/off cloud sync. Project URL, anon key and shop account are
/// built into the app — no typing on each phone.
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  bool _enabled = false;
  bool _busy = false;
  bool _canConnect = false;
  String _status = '';
  StreamSubscription<String>? _statusSub;

  @override
  void initState() {
    super.initState();
    _load();
    _statusSub = SyncService.instance.statusStream.listen((msg) {
      if (mounted) setState(() => _status = msg);
    });
  }

  Future<void> _load() async {
    final enabled = await SyncService.instance.isEnabled();
    final canConnect = await SyncService.instance.canConnect;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _canConnect = canConnect;
      if (SyncService.instance.isSignedIn) {
        _status = 'Live sync on';
      } else if (enabled) {
        _status = 'Enabled — connecting…';
      } else {
        _status = 'Cloud sync off';
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
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

  Future<void> _toggle(bool value) => _run(() async {
        await SyncService.instance.setEnabled(value);
        setState(() => _enabled = value);
      });

  Future<void> _reconnect() =>
      _run(() => SyncService.instance.connectAndSync());

  Future<void> _push() => _run(() => SyncService.instance.pushAll());

  Future<void> _pull() => _run(() => SyncService.instance.pullAll());

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = SyncService.instance.isSignedIn;
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
                  Text('Multi-device sync',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Turn this on and every phone with this app shares the '
                    'same inventory and staff logins automatically.\n\n'
                    'No email or API keys to type on the phone — those are '
                    'built into the app.\n\n'
                    'First time: in Supabase turn OFF Authentication → '
                    'Providers → Email → Confirm email, then tap Connect.',
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
                  'This APK does not include Supabase project settings yet. '
                  'Send your Project URL and anon public key so they can be '
                  'built into the next APK — then just flip this switch.',
                  style: TextStyle(height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable cloud sync'),
            subtitle: Text(
              ready
                  ? 'Uses the shop project built into this app'
                  : 'Waiting for built-in project settings',
            ),
            value: _enabled,
            onChanged: (_busy || !ready) ? null : _toggle,
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                signedIn ? Icons.cloud_done : Icons.cloud_off,
                color: signedIn ? Colors.green : Colors.grey,
              ),
              title: Text(signedIn ? 'Connected' : 'Not connected'),
              subtitle: Text(
                signedIn
                    ? 'Phones will stay in sync while online'
                    : (_status.isNotEmpty ? _status : 'Tap reconnect'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _reconnect,
              icon: const Icon(Icons.sync),
              label: Text(signedIn ? 'Sync now' : 'Connect'),
            ),
            if (signedIn) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pull,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Pull'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _push,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Push'),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status, style: TextStyle(color: Colors.grey.shade800)),
          ],
          const SizedBox(height: 24),
          Text(
            'Shop account: ${SupabaseConfig.shopEmail}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
