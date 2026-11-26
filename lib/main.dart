import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dentpass/app.dart';
import 'package:dentpass/config.dart';
import 'package:dentpass/locale_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await initializeDateFormatting();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    // On the web, email links (reset password, confirm email) may open in Safari while the app
    // was added to the home screen, which keeps separate storage. The implicit flow works across both.
    authOptions: FlutterAuthClientOptions(authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce),
  );
  localeController = await LocaleController.load();

  runApp(const DentPassApp());
}

/// Shown when the app is started without the Supabase keys (see README).
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Start the app with --dart-define=SUPABASE_URL=... and '
              '--dart-define=SUPABASE_ANON_KEY=... (see README.md).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
