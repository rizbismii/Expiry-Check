import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sync_service.dart';

/// Configure Supabase live sync: project URL/anon key + shared shop account.
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _enabled = false;
  bool _busy = false;
  bool _obscureKey = true;
  bool _obscurePassword = true;
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
    final (url, key, enabled) = await SyncService.instance.loadConfig();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = url;
      _keyCtrl.text = key;
      _enabled = enabled;
      _status = SyncService.instance.isSignedIn
          ? 'Signed in as ${SyncService.instance.syncEmail}'
          : (enabled ? 'Configured — sign in to sync' : 'Cloud sync off');
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

  Future<void> _saveConfig() => _run(() async {
        await SyncService.instance.saveConfig(
          url: _urlCtrl.text,
          anonKey: _keyCtrl.text,
          enabled: _enabled,
        );
        setState(() => _status = _enabled
            ? 'Saved. Sign in with the shop sync email below.'
            : 'Cloud sync disabled');
      });

  Future<void> _signUp() => _run(() async {
        await SyncService.instance.saveConfig(
          url: _urlCtrl.text,
          anonKey: _keyCtrl.text,
          enabled: true,
        );
        setState(() => _enabled = true);
        await SyncService.instance
            .signUp(_emailCtrl.text, _passwordCtrl.text);
      });

  Future<void> _signIn() => _run(() async {
        await SyncService.instance.saveConfig(
          url: _urlCtrl.text,
          anonKey: _keyCtrl.text,
          enabled: true,
        );
        setState(() => _enabled = true);
        await SyncService.instance
            .signIn(_emailCtrl.text, _passwordCtrl.text);
      });

  Future<void> _signOut() => _run(() => SyncService.instance.signOutSync());

  Future<void> _push() => _run(() => SyncService.instance.pushAll());

  Future<void> _pull() => _run(() => SyncService.instance.pullAll());

  @override
  void dispose() {
    _statusSub?.cancel();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = SyncService.instance.isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync (Supabase)')),
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
                  Text('How it works',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Create a free project at supabase.com\n'
                    '2. Paste supabase/schema.sql into the SQL Editor and Run '
                    '(safe to re-run if it errored before)\n'
                    '3. If you already set up sync earlier, also run '
                    'supabase/schema_staff_users.sql so staff logins sync\n'
                    '4. If needed, enable Realtime for products + stores + '
                    'staff_users under Database → Publications\n'
                    '5. Paste Project URL + anon public key below\n'
                    '6. Create one shared shop email/password and sign in '
                    'on every device with those same credentials\n'
                    '7. Inventory and staff users then sync live across devices',
                    style: TextStyle(height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable cloud sync'),
            value: _enabled,
            onChanged: _busy
                ? null
                : (v) => setState(() => _enabled = v),
          ),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Supabase Project URL',
              hintText: 'https://xxxx.supabase.co',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            decoration: InputDecoration(
              labelText: 'Anon public key',
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _saveConfig,
            icon: const Icon(Icons.save),
            label: const Text('Save project settings'),
          ),
          const SizedBox(height: 24),
          Text('Shop sync account',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            signedIn
                ? 'Signed in as ${SyncService.instance.syncEmail}'
                : 'Use the same email/password on every phone in the shop.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _signUp,
                  child: const Text('Create account'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Sign in'),
                ),
              ),
            ],
          ),
          if (signedIn) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out of sync')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pull,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Pull now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _push,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Push now'),
                  ),
                ),
              ],
            ),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status, style: TextStyle(color: Colors.grey.shade800)),
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(
                text: 'See supabase/schema.sql in the Expiry-Check repo',
              ));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Open supabase/schema.sql in the project and run it in Supabase SQL Editor')),
              );
            },
            icon: const Icon(Icons.code),
            label: const Text('Schema file: supabase/schema.sql'),
          ),
        ],
      ),
    );
  }
}
