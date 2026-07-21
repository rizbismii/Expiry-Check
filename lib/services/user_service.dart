import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';

/// Username + password sign-in, fully on-device.
///
/// - The built-in admin account is `admin` / [adminPassword].
/// - The admin creates staff accounts (up to 10) in Manage Users; only the
///   admin can see that list.
/// - The signed-in username is stamped on entries ("Created By") and the
///   deletion log.
class UserService {
  UserService._();
  static final UserService instance = UserService._();

  static const adminUsername = 'admin';
  static const adminPassword = 'admin555777';

  static const _usernameKey = 'profile_username';
  static const _isAdminKey = 'profile_is_admin';

  Future<bool> get isSignedIn async => (await username) != null;

  Future<String?> get username async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_usernameKey);
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<bool> get isAdmin async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isAdminKey) ?? false;
  }

  /// Validates credentials against the admin account or the staff users the
  /// admin created. Saves the session on success.
  Future<bool> signIn(String username, String password) async {
    final typed = username.trim();
    final pass = password.trim();
    if (typed.toLowerCase() == adminUsername) {
      if (pass != adminPassword) return false;
      await _saveSession(adminUsername, isAdmin: true);
      return true;
    }
    final user = await DatabaseService.instance.findUser(typed, pass);
    if (user == null) return false;
    await _saveSession(user.username, isAdmin: false);
    return true;
  }

  Future<void> _saveSession(String username, {required bool isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
    await prefs.setBool(_isAdminKey, isAdmin);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_isAdminKey);
  }
}
