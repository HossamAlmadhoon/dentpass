import 'package:flutter/material.dart';

import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/profile_screen.dart';
import 'package:dentpass/theme.dart';

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.onCheckAgain, this.suspended = false});
  final VoidCallback onCheckAgain;

  /// Shows the "account suspended" message instead of "we're checking your details".
  final bool suspended;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(actions: const [LanguageSwitchButton()]),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: suspended ? AppColors.dangerTint : AppColors.amberTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  suspended ? Icons.block : Icons.hourglass_top_rounded,
                  color: suspended ? AppColors.danger : AppColors.amber,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(suspended ? t.suspendedTitle : t.pendingTitle,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 10),
              Text(suspended ? t.suspendedBody : t.pendingBody, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.body)),
              const SizedBox(height: 28),
              FilledButton(onPressed: onCheckAgain, child: Text(t.checkAgain)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: repo.signOut, child: Text(t.signOut)),
            ],
          ),
        ),
      ),
    );
  }
}
