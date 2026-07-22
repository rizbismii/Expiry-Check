/// Built-in Supabase sync settings for every install of this app.
///
/// Only the Project URL + anon/publishable key are required. There is **no**
/// sync email/password — that was causing bounced Supabase emails.
///
/// Staff logins (admin → Manage users) are separate and still sync via the
/// `staff_users` table. Cloud sync itself uses [shopId] with the anon key.
///
/// Override at build time if needed:
/// `flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
class SupabaseConfig {
  SupabaseConfig._();

  /// Project URL, e.g. https://abcdxyz.supabase.co
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// anon / publishable public key (safe to ship in the app).
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Shared shop namespace for all devices of this install. Not an email.
  static const shopId = String.fromEnvironment(
    'SUPABASE_SHOP_ID',
    defaultValue: 'expiry-check-shop',
  );

  // -------------------------------------------------------------------------
  // Paste your project values here once (or use --dart-define when building).
  // -------------------------------------------------------------------------
  static const _fallbackUrl = 'https://lzaqzahjfjugabjdinbb.supabase.co';
  static const _fallbackAnonKey =
      'sb_publishable_gurLIiGQYajTMEMnKjHXvA_AAX3fsIc';

  static String get effectiveUrl =>
      url.isNotEmpty ? url : _fallbackUrl;

  static String get effectiveAnonKey =>
      anonKey.isNotEmpty ? anonKey : _fallbackAnonKey;

  static bool get isBuiltIn =>
      effectiveUrl.isNotEmpty && effectiveAnonKey.isNotEmpty;
}
