import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/user_service.dart';

/// One-time sign-in: username + email, passcode sent to the email, code
/// typed back in to verify. The profile is stored on-device.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final passcode = UserService.generatePasscode();
    final opened = await UserService.instance.startVerification(
      username: _usernameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      passcode: passcode,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _codeSent = true;
    });
    _snack(opened
        ? 'Send the email that just opened, then enter the passcode from '
            'your inbox.'
        : 'No email app found — could not send the passcode.');
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    final ok = await UserService.instance.verifyPasscode(_codeCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _snack('Incorrect or expired passcode. Tap "Send passcode" to retry.');
    }
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
        appBar: AppBar(title: const Text('Sign in')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.inventory_2, size: 64, color: scheme.primary),
              const SizedBox(height: 8),
              const Text(
                'Expiry Check',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Your name is attached to the stock you add or delete, '
                'and appears on Excel reports.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Username is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Email is required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _sendCode,
                icon: const Icon(Icons.forward_to_inbox),
                label: Text(_codeSent ? 'Resend passcode' : 'Send passcode'),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'One-time passcode',
                    hintText: '6-digit code from the email',
                    prefixIcon: Icon(Icons.pin),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _verify,
                  icon: const Icon(Icons.login),
                  label: const Text('Verify and sign in'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
