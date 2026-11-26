import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/platform/url_cleanup.dart';
import 'package:dentpass/screens/basic_details_screen.dart';
import 'package:dentpass/screens/home_shell.dart';
import 'package:dentpass/screens/password_screens.dart';
import 'package:dentpass/screens/pending_screen.dart';
import 'package:dentpass/screens/sign_in_screen.dart';
import 'package:dentpass/ui/widgets.dart';

/// Signed out → sign in. Signed in → basic details once, then the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;
  Session? _session = repo.db.auth.currentSession;
  // True after opening a password reset link (?reset=1 on the web, or the recovery event).
  bool _recovering = kIsWeb && Uri.base.queryParameters['reset'] == '1';

  @override
  void initState() {
    super.initState();
    _sub = repo.db.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _session = state.session;
        if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        // A normal sign-in (for example after an expired reset link) goes to the app as usual.
        if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.signedOut) {
          _recovering = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return const SignInScreen();
    if (_recovering) {
      return SetPasswordScreen(onDone: () {
        cleanUpAddressBar();
        setState(() => _recovering = false);
      });
    }
    return _ProfileGate(key: ValueKey(session.user.id));
  }
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({super.key});

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Future<Profile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = repo.myProfile();
  }

  void _reload() => setState(() => _profile = repo.myProfile());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile>(
      future: _profile,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(body: ErrorView(error: snap.error!, onRetry: _reload));
        }
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final p = snap.data!;
        // Papers are optional: everyone with a name and mobile gets in. Posting asks for papers.
        if (p.status == VerificationStatus.suspended) return PendingScreen(onCheckAgain: _reload, suspended: true);
        if (!p.hasBasics) return BasicDetailsScreen(profile: p, onSaved: _reload);
        return HomeShell(profile: p, onProfileChanged: _reload);
      },
    );
  }
}
