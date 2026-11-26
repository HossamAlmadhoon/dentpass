import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/verify_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

/// Opens the papers form. Reloads the profile when papers were sent.
Future<void> openVerify(BuildContext context, Profile profile, VoidCallback onChanged) async {
  final t = AppLocalizations.of(context);
  final sent = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => VerifyScreen(profile: profile)),
  );
  if (sent == true && context.mounted) {
    showMessage(context, t.verifySent);
    onChanged();
  }
}

/// What the Post tab shows to members who are not verified yet.
class GetVerifiedScreen extends StatelessWidget {
  const GetVerifiedScreen({super.key, required this.profile, required this.onChanged});
  final Profile profile;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final checking = profile.status == VerificationStatus.pending;
    final rejected = profile.status == VerificationStatus.rejected;

    return Scaffold(
      appBar: AppBar(title: Text(t.tabPost, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checking ? AppColors.amberTint : AppColors.nileTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                checking ? Icons.hourglass_top_rounded : Icons.verified_outlined,
                color: checking ? AppColors.amber : AppColors.nile,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            Text(checking ? t.papersCheckingTitle : t.postNeedsVerifyTitle,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 10),
            Text(checking ? t.papersCheckingBody : t.postNeedsVerifyBody,
                style: const TextStyle(fontSize: 16, height: 1.55, color: AppColors.body)),
            if (rejected) ...[
              const SizedBox(height: 16),
              _RejectedNote(profile: profile),
            ],
            const SizedBox(height: 28),
            if (checking)
              OutlinedButton(onPressed: onChanged, child: Text(t.checkAgain))
            else
              FilledButton.icon(
                onPressed: () => openVerify(context, profile, onChanged),
                icon: const Icon(Icons.verified_outlined),
                label: Text(rejected ? t.sendAgain : t.getVerified),
              ),
          ],
        ),
      ),
    );
  }
}

/// A short card at the top of Home for members without the verified mark.
class VerifyBanner extends StatelessWidget {
  const VerifyBanner({super.key, required this.profile, required this.onChanged});
  final Profile profile;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (profile.isVerified) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final checking = profile.status == VerificationStatus.pending;
    final rejected = profile.status == VerificationStatus.rejected;
    final color = checking ? AppColors.amber : AppColors.nile;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(checking ? Icons.hourglass_top_rounded : Icons.verified_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              checking ? t.papersCheckingTitle : (rejected ? t.rejectedTitle : t.getVerifiedTitle),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(checking ? t.papersCheckingBody : t.getVerifiedBody, style: const TextStyle(color: AppColors.body, height: 1.45)),
        if (!checking) ...[
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => openVerify(context, profile, onChanged),
            child: Text(rejected ? t.sendAgain : t.getVerified),
          ),
        ],
      ]),
    );
  }
}

class _RejectedNote extends StatelessWidget {
  const _RejectedNote({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.dangerTint, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.rejectedTitle, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
        if ((profile.rejectionReason ?? '').isNotEmpty) Text(t.rejectedReason(profile.rejectionReason!)),
      ]),
    );
  }
}
