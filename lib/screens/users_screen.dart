import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/database_service.dart';

/// Admin-only staff account management (up to 10 users). Passwords are
/// visible here so the admin can hand them out.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await DatabaseService.instance.getUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _addUser() async {
    final result = await _showUserDialog(title: 'New user');
    if (result == null) return;
    final error = await DatabaseService.instance
        .addUser(result.$1, result.$2);
    if (error != null) {
      _snack(error);
      return;
    }
    await _load();
    _snack('User "${result.$1}" created.');
  }

  Future<void> _editPassword(AppUser user) async {
    final result = await _showUserDialog(
      title: 'Change password',
      username: user.username,
      usernameLocked: true,
      password: user.password,
    );
    if (result == null) return;
    await DatabaseService.instance.updateUserPassword(user.id!, result.$2);
    await _load();
    _snack('Password updated for "${user.username}".');
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Remove "${user.username}"? They will no longer be '
            'able to sign in. Their name stays on entries they created.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseService.instance.deleteUser(user.id!);
    await _load();
    _snack('User "${user.username}" deleted.');
  }

  /// Returns (username, password) or null.
  Future<(String, String)?> _showUserDialog({
    required String title,
    String username = '',
    String password = '',
    bool usernameLocked = false,
  }) {
    final usernameCtrl = TextEditingController(text: username);
    final passwordCtrl = TextEditingController(text: password);
    final formKey = GlobalKey<FormState>();
    return showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: usernameCtrl,
                enabled: !usernameLocked,
                autofocus: !usernameLocked,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Username is required';
                  if (value.toLowerCase() == 'admin') {
                    return '"admin" is reserved';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordCtrl,
                autofocus: usernameLocked,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => (v == null || v.length < 4)
                    ? 'Password must be at least 4 characters'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context,
                    (usernameCtrl.text.trim(), passwordCtrl.text.trim()));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('Manage users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${_users.length} of ${DatabaseService.maxUsers} staff '
                      'accounts. Only the admin can see this list, including '
                      'passwords.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_users.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No staff accounts yet.\nTap "Add user" to create one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _users.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                  _users[i].username[0].toUpperCase()),
                            ),
                            title: Text(_users[i].username),
                            subtitle:
                                Text('Password: ${_users[i].password}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Change password',
                                  icon: const Icon(Icons.key),
                                  onPressed: () => _editPassword(_users[i]),
                                ),
                                IconButton(
                                  tooltip: 'Delete user',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteUser(_users[i]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _users.length >= DatabaseService.maxUsers ? null : _addUser,
        icon: const Icon(Icons.person_add),
        label: const Text('Add user'),
      ),
    );
  }
}
