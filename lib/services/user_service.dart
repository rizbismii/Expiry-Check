import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Local sign-in with a one-time passcode delivered by email.
///
/// No backend is used (keeps running costs at zero): the app generates the
/// passcode and opens the user's own email app with a message addressed to
/// the entered address. Entering the code back into the app confirms the
/// address and saves the profile on-device. This identifies who created
/// or deleted stock entries; it is identity labelling, not account security.
class UserService {
  UserService._();
  static final UserService instance = UserService._();

  static const _usernameKey = 'profile_username';
  static const _emailKey = 'profile_email';
  static const _pendingUsernameKey = 'pending_username';
  static const _pendingEmailKey = 'pending_email';
  static const _pendingCodeKey = 'pending_passcode';
  static const _pendingExpiryKey = 'pending_passcode_expiry';

  static const passcodeValidity = Duration(minutes: 10);

  Future<bool> get isSignedIn async => (await username) != null;

  Future<String?> get username async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  Future<String?> get email async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  static String generatePasscode() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  /// Stores the pending profile + passcode and opens the user's email app
  /// with the code addressed to [email]. Returns false when no email app
  /// could be opened (the caller may show the code instead).
  Future<bool> startVerification({
    required String username,
    required String email,
    required String passcode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingUsernameKey, username);
    await prefs.setString(_pendingEmailKey, email);
    await prefs.setString(_pendingCodeKey, passcode);
    await prefs.setInt(_pendingExpiryKey,
        DateTime.now().add(passcodeValidity).millisecondsSinceEpoch);

    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: Uri.encodeFull(
          'subject=Expiry Check sign-in passcode&body=Your Expiry Check '
          'one-time passcode is: $passcode\n\nIt expires in 10 minutes.'),
    );
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Verifies the typed passcode; on success the pending profile becomes the
  /// signed-in profile.
  Future<bool> verifyPasscode(String typed) async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingCodeKey);
    final expiry = prefs.getInt(_pendingExpiryKey) ?? 0;
    if (code == null || typed.trim() != code) return false;
    if (DateTime.now().millisecondsSinceEpoch > expiry) return false;
    await prefs.setString(
        _usernameKey, prefs.getString(_pendingUsernameKey) ?? '');
    await prefs.setString(_emailKey, prefs.getString(_pendingEmailKey) ?? '');
    await prefs.remove(_pendingUsernameKey);
    await prefs.remove(_pendingEmailKey);
    await prefs.remove(_pendingCodeKey);
    await prefs.remove(_pendingExpiryKey);
    return true;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_emailKey);
  }
}
