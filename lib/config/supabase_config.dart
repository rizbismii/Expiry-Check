/// Built-in Supabase sync settings for every install of this app.
///
/// Fill [url] and [anonKey] once (from Supabase → Project Settings → API).
/// [shopEmail] / [shopPassword] are the shared cloud account — phones never
/// type these; the app signs in automatically when sync is enabled.
///
/// You can also override at build time:
/// `flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
class SupabaseConfig {
  SupabaseConfig._();

  /// Project URL, e.g. https://abcdxyz.supabase.co
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '', // set below in [_fallbackUrl] or via --dart-define
  );

  /// anon / publishable public key (safe to ship in the app).
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Shared shop sync login (not a staff username). Auto sign-in on every phone.
  static const shopEmail = String.fromEnvironment(
    'SUPABASE_SHOP_EMAIL',
    defaultValue: 'expiry.check.shop@gmail.com',
  );

  static const shopPassword = String.fromEnvironment(
    'SUPABASE_SHOP_PASSWORD',
    defaultValue: 'ExpiryCheckShopSync1!',
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
