/// Supabase keys are passed at build time, never committed:
/// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The public web address, used in shared slot links.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://hossamalmadhoon.github.io/dentpass/');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
