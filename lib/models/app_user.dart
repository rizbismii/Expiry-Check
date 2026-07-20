/// Staff account created by the admin. Passwords are stored on-device so the
/// admin can view and hand them out; this is a single-shop local app, not a
/// hosted account system.
class AppUser {
  final int? id;
  final String username;
  final String password;

  const AppUser({this.id, required this.username, required this.password});

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'password': password,
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as int?,
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
      );
}
