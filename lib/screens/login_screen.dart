import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/store.dart';
import '../services/database_service.dart';
import '../services/user_service.dart';

/// Two-step sign-in: username + password, then store branch selection.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  // Step 2 state.
  bool _authenticated = false;
  List<Store> _stores = [];
  int? _storeId;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await UserService.instance
        .signIn(_usernameCtrl.text, _passwordCtrl.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      _snack('Incorrect username or password.');
      return;
    }
    final stores = await DatabaseService.instance.getStores();
    final prefs = await SharedPreferences.getInstance();
    final savedStore = prefs.getInt('selected_store_id');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _authenticated = true;
      _stores = stores;
      _storeId = stores.any((s) => s.id == savedStore)
          ? savedStore
          : (stores.isNotEmpty ? stores.first.id : null);
    });
  }

  Future<void> _continueToStore() async {
    if (_storeId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_store_id', _storeId!);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
            title: Text(_authenticated ? 'Select store' : 'Sign in')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.inventory_2, size: 64, color: scheme.primary),
            const SizedBox(height: 8),
            const Text(
              'Expiry Check',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (!_authenticated) _buildCredentialsStep() else _buildStoreStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
            autofillHints: const [AutofillHints.username],
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Username is required'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _signIn(),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Password is required' : null,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 12),
          Text(
            'Ask the admin for your username and password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Signed in as ${_usernameCtrl.text.trim()}. '
          'Which store are you working in?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final store in _stores)
                RadioListTile<int>(
                  value: store.id,
                  groupValue: _storeId,
                  title: Text(store.name),
                  secondary: const Icon(Icons.store),
                  onChanged: (v) => setState(() => _storeId = v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _storeId == null ? null : _continueToStore,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ],
    );
  }
}
