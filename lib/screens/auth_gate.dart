import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/screens/home_shell.dart';
import 'package:dentpass/screens/pending_screen.dart';
import 'package:dentpass/screens/sign_in_screen.dart';
import 'package:dentpass/screens/verify_screen.dart';
import 'package:dentpass/ui/widgets.dart';

/// Signed out → sign in. Signed in → the screen that matches the member's verification status.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;
  Session? _session = repo.db.auth.currentSession;

  @override
  void initState() {
    super.initState();
    _sub = repo.db.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _session = state.session);
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
        return switch (p.status) {
          VerificationStatus.approved => HomeShell(profile: p, onProfileChanged: _reload),
          VerificationStatus.pending => PendingScreen(onCheckAgain: _reload),
          VerificationStatus.unverified || VerificationStatus.rejected =>
            VerifyScreen(profile: p, onSubmitted: _reload),
        };
      },
    );
  }
}
