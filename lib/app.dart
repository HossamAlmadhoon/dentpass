import 'package:flutter/material.dart';

import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/locale_controller.dart';
import 'package:dentpass/screens/auth_gate.dart';
import 'package:dentpass/theme.dart';

class DentPassApp extends StatelessWidget {
  const DentPassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeController,
      builder: (context, locale, _) => MaterialApp(
        title: 'DentPass',
        debugShowCheckedModeBanner: false,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildTheme(),
        home: const AuthGate(),
      ),
    );
  }
}
