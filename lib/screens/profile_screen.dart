import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/locale_controller.dart';
import 'package:dentpass/screens/admin_screen.dart';
import 'package:dentpass/screens/alerts_screen.dart';
import 'package:dentpass/screens/edit_profile_screen.dart';
import 'package:dentpass/screens/info_screens.dart';
import 'package:dentpass/screens/member_screen.dart';
import 'package:dentpass/screens/password_screens.dart';
import 'package:dentpass/screens/verify_gate.dart';
import 'package:dentpass/services/notifications.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile, required this.onChanged});
  final Profile profile;
  final VoidCallback onChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Future<Member?> _me = repo.member(widget.profile.id);
  final _push = PhoneNotifications.instance;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _push.addListener(_changed);
  }

  @override
  void dispose() {
    _push.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _setNotifications(bool on) async {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    try {
      if (on) {
        await _push.enable(lang: lang);
        if (mounted) showMessage(context, t.notificationsOn);
      } else {
        await _push.disable();
      }
    } on PushError catch (e) {
      if (mounted) showMessage(context, e.reason == 'denied' ? t.notificationsBlocked : t.errGeneric);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  Widget _notificationsTile(AppLocalizations t) {
    final s = _push.status;
    final note = switch (s) {
      PushStatus.install => t.addToHomeFirst,
      PushStatus.unsupported => t.notificationsUnsupported,
      PushStatus.denied => t.notificationsBlocked,
      _ => t.notificationsWhy,
    };
    final canToggle = (s == PushStatus.notAsked || s == PushStatus.granted) && (_push.ready || _push.enabled) && !_push.busy;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: Text(t.phoneNotifications, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(note, style: const TextStyle(height: 1.4)),
        value: _push.enabled,
        onChanged: canToggle ? _setNotifications : null,
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final t = AppLocalizations.of(context);
    if (!await confirmAction(context, title: t.deleteAccount, body: t.deleteAccountConfirm, action: t.delete, danger: true)) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await repo.deleteMyAccount(); // signs out; the app returns to sign-in
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        showMessage(context, errorText(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final p = widget.profile;

    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: Text(t.tabProfile, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Row(children: [
            Avatar(name: p.fullName, photoUrl: p.avatarPath == null ? null : repo.avatarUrl(p.avatarPath!), radius: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                  [roleName(t, p.role), areaName(context, p.area)].where((s) => s.isNotEmpty).join(lang == 'ar' ? '، ' : ', '),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  if (p.isVerified) ...[
                    const Icon(Icons.verified, size: 16, color: AppColors.nile),
                    const SizedBox(width: 4),
                    Text(t.statusApproved, style: const TextStyle(color: AppColors.nile, fontWeight: FontWeight.w700)),
                  ] else
                    Text(
                      p.status == VerificationStatus.pending ? t.papersCheckingShort : t.statusNotVerified,
                      style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700),
                    ),
                  const SizedBox(width: 10),
                  FutureBuilder<Member?>(
                    future: _me,
                    builder: (context, snap) => snap.data == null
                        ? const SizedBox.shrink()
                        : snap.data!.reviews == 0 || snap.data!.rating == null
                            ? Text(t.noRatingsYet, style: const TextStyle(fontSize: 13, color: AppColors.muted))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Stars(rating: snap.data!.rating!, size: 15),
                                const SizedBox(width: 4),
                                Text('${snap.data!.rating!.toStringAsFixed(1)} (${snap.data!.reviews})',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              ]),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          if (!p.isVerified && p.status != VerificationStatus.pending) ...[
            FilledButton.icon(
              onPressed: () => openVerify(context, p, widget.onChanged),
              icon: const Icon(Icons.verified_outlined),
              label: Text(p.status == VerificationStatus.rejected ? t.sendAgain : t.getVerified),
            ),
            const SizedBox(height: 20),
          ],
          if (p.isAdmin) ...[
            FilledButton.icon(
              onPressed: () => open(const AdminScreen()),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text(t.reviewMembers),
            ),
            const SizedBox(height: 20),
          ],
          _Group(children: [
            _Row(
              icon: Icons.edit_outlined,
              title: t.editProfile,
              subtitle: (p.instapay ?? '').isEmpty ? t.addInstapayNudge : t.instapayShort(p.instapay!),
              onTap: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p)),
                );
                if (saved == true) widget.onChanged();
              },
            ),
            _Row(icon: Icons.badge_outlined, title: t.viewMyPage, onTap: () => open(MemberScreen(userId: p.id, viewer: p))),
          ]),
          const SizedBox(height: 14),
          _notificationsTile(t),
          const SizedBox(height: 14),
          _Group(children: [
            _Row(icon: Icons.notification_add_outlined, title: t.myAlerts, subtitle: t.alertsShort, onTap: () => open(const AlertsScreen())),
          ]),
          const SizedBox(height: 24),
          Text(t.language, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.body)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {lang},
            onSelectionChanged: (s) {
              localeController.setLanguage(s.first);
              repo.saveLanguage(s.first);
            },
          ),
          const SizedBox(height: 24),
          _Group(children: [
            _Row(icon: Icons.help_outline, title: t.help, onTap: () => open(const HelpScreen())),
            _Row(
              icon: Icons.lock_outline,
              title: t.changePassword,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => SetPasswordScreen(onDone: () => Navigator.pop(ctx))),
              ),
            ),
            _Row(icon: Icons.logout, title: t.signOut, onTap: repo.signOut, showArrow: false),
          ]),
          const SizedBox(height: 20),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _deleting ? null : _deleteAccount,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(t.deleteAccount),
          ),
        ],
      ),
    );
  }
}

/// A white card holding a few settings rows, with lines between them.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            children[i],
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap, this.subtitle, this.showArrow = true});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.body),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: showArrow ? const Icon(Icons.chevron_right, color: AppColors.muted) : null,
        onTap: onTap,
      );
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
