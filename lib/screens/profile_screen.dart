import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/locale_controller.dart';
import 'package:dentpass/screens/admin_screen.dart';
import 'package:dentpass/screens/password_screens.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.profile, required this.onChanged});
  final Profile profile;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(t.tabProfile, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.ink,
              foregroundColor: Colors.white,
              child: Text(initials(profile.fullName), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                  [roleName(t, profile.role), areaName(context, profile.area)].where((s) => s.isNotEmpty).join(lang == 'ar' ? '، ' : ', '),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.verified, size: 16, color: AppColors.nile),
                  const SizedBox(width: 4),
                  Text(t.statusApproved, style: const TextStyle(color: AppColors.nile, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 28),
          Text(t.language, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {lang},
            onSelectionChanged: (s) => localeController.setLanguage(s.first),
          ),
          if (profile.isAdmin) ...[
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text(t.reviewMembers),
            ),
          ],
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (ctx) => SetPasswordScreen(onDone: () => Navigator.pop(ctx))),
            ),
            icon: const Icon(Icons.lock_outline),
            label: Text(t.changePassword),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: repo.signOut,
            icon: const Icon(Icons.logout),
            label: Text(t.signOut),
          ),
        ],
      ),
    );
  }
}

/// A small "English" / "العربية" switch for screens before sign-in.
class LanguageSwitchButton extends StatelessWidget {
  const LanguageSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return TextButton(
      onPressed: () => localeController.setLanguage(isAr ? 'en' : 'ar'),
      child: Text(isAr ? 'English' : 'العربية'),
    );
  }
}
