import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/screens/review_sheet.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/services/location.dart';
import 'package:dentpass/services/notifications.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// The personal top of Explore: a greeting, your next slot, what you host next,
/// requests waiting for you, and a nudge to turn on phone notifications.
class HomeHeader extends StatefulWidget {
  const HomeHeader({super.key, required this.profile, required this.refreshKey});
  final Profile profile;

  /// Changes whenever Explore reloads, so the header reloads with it.
  final int refreshKey;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  late Future<HomeSummary> _home = repo.home();
  late Future<Booking?> _toRate = _findToRate();

  /// A finished booking from the last two weeks that hasn't been rated yet.
  Future<Booking?> _findToRate() async {
    try {
      final results = await Future.wait([repo.myBookings(), repo.myRatedBookingIds()]);
      final rated = results[1] as Set<String>;
      final since = DateTime.now().subtract(const Duration(days: 14));
      for (final b in results[0] as List<Booking>) {
        final s = b.slot;
        if (s != null && b.status == BookingStatus.accepted && s.hasEnded && s.endsAt.isAfter(since) && !rated.contains(b.id)) {
          return b;
        }
      }
    } catch (_) {}
    return null;
  }
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps "In 3 h" up to date
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant HomeHeader old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) {
      _home = repo.home();
      _toRate = _findToRate();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _firstName(String full) {
    final parts = full.replaceAll(RegExp(r'^(Dr\.?|د\.?)\s*', caseSensitive: false), '').trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? full : parts.first;
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() => _home = repo.home());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(t.hello(_firstName(widget.profile.fullName)),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
      ),
      const SizedBox(height: 12),
      FutureBuilder<HomeSummary>(
        future: _home,
        builder: (context, snap) {
          final h = snap.data;
          if (h == null) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (h.next != null) ...[
              _NextSlotCard(next: h.next!, onOpen: () => _open(SlotDetailScreen(slotId: h.next!.slotId, profile: widget.profile))),
              const SizedBox(height: 12),
            ],
            if (h.waiting > 0 && h.hostingNext != null) ...[
              _Banner(
                icon: Icons.inbox_outlined,
                color: AppColors.amber,
                tint: AppColors.amberTint,
                text: t.requestsWaiting(h.waiting),
                onTap: () => _open(ManageSlotScreen(slotId: h.hostingNext!.slotId, profile: widget.profile)),
              ),
              const SizedBox(height: 12),
            ] else if (h.hostingNext != null) ...[
              _Banner(
                icon: Icons.event_available_outlined,
                color: AppColors.nile,
                tint: AppColors.nileTint,
                text: '${t.youHostNext}: ${h.hostingNext!.title}\n'
                    '${_relativeDay(context, h.hostingNext!.startsAt)} · ${t.acceptedCount(h.hostingNext!.accepted)}',
                onTap: () => _open(ManageSlotScreen(slotId: h.hostingNext!.slotId, profile: widget.profile)),
              ),
              const SizedBox(height: 12),
            ],
          ]);
        },
      ),
      FutureBuilder<Booking?>(
        future: _toRate,
        builder: (context, snap) {
          final b = snap.data;
          if (b == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RateCard(
              booking: b,
              onRate: (stars) async {
                final t = AppLocalizations.of(context);
                if (await showReviewSheet(context, bookingId: b.id, title: t.rateHost, stars: stars) && mounted) {
                  setState(() => _toRate = _findToRate());
                }
              },
            ),
          );
        },
      ),
      const _NotificationsPrompt(),
    ]);
  }
}

String _relativeDay(BuildContext context, DateTime d) => '${dayText(context, d)} ${time(context, d)}';

class _NextSlotCard extends StatelessWidget {
  const _NextSlotCard({required this.next, required this.onOpen});
  final NextSlot next;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ks = kindStyle(next.kind);
    final now = DateTime.now();
    final hours = next.startsAt.difference(now).inHours;
    final badge = next.startsAt.isBefore(now)
        ? t.happeningNow
        : hours < 24
            ? t.inHours(hours < 1 ? 1 : hours)
            : _relativeDay(context, next.startsAt);

    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(t.yourNextSlot, style: const TextStyle(color: Color(0xFFC9D1CB), fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: ks.tint, borderRadius: BorderRadius.circular(999)),
                child: Text(badge, style: TextStyle(color: ks.ink, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(next.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 4),
            Text(
              [
                // The day is in the badge above; here only the hours
                hoursText(context, next.startsAt, next.endsAt),
                next.hostName,
                next.address.isNotEmpty ? next.address : areaName(context, next.area),
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFC9D1CB), height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(children: [
              if (next.lat != null && next.lng != null)
                _CardAction(
                  icon: Icons.directions_outlined,
                  label: t.directions,
                  onTap: () => launchUrl(mapsLink(next.lat!, next.lng!), mode: LaunchMode.externalApplication),
                ),
              if (next.hostPhone != null) ...[
                _CardAction(icon: Icons.call_outlined, label: t.call, onTap: () => callNumber(next.hostPhone!)),
                _CardAction(icon: Icons.chat_outlined, label: t.whatsapp, onTap: () => openWhatsApp(next.hostPhone!)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF56616B)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.tint, required this.text, required this.onTap});
  final IconData icon;
  final Color color;
  final Color tint;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, height: 1.4))),
              Icon(Icons.chevron_right, color: color),
            ]),
          ),
        ),
      );
}

const _promptKey = 'notifications_prompt_dismissed_v1';

/// Asks once to turn on phone notifications; explains "add to home screen" on iPhone.
class _NotificationsPrompt extends StatefulWidget {
  const _NotificationsPrompt();

  @override
  State<_NotificationsPrompt> createState() => _NotificationsPromptState();
}

class _NotificationsPromptState extends State<_NotificationsPrompt> {
  final _push = PhoneNotifications.instance;
  bool _dismissed = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _dismissed = p.getBool(_promptKey) ?? false);
    });
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

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    (await SharedPreferences.getInstance()).setBool(_promptKey, true);
  }

  Future<void> _turnOn() async {
    final t = AppLocalizations.of(context);
    try {
      await _push.enable(lang: Localizations.localeOf(context).languageCode);
      if (mounted) showMessage(context, t.notificationsOn);
    } on PushError catch (e) {
      if (mounted) showMessage(context, e.reason == 'denied' ? t.notificationsBlocked : t.errGeneric);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = _push.status;
    if (_dismissed || _push.enabled || s == PushStatus.unsupported || s == PushStatus.denied) {
      return const SizedBox.shrink();
    }
    final install = s == PushStatus.install;
    if (!install && !_push.ready) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.notifications_active_outlined, color: AppColors.nile),
          const SizedBox(width: 10),
          Expanded(child: Text(t.turnOnNotifications, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ]),
        const SizedBox(height: 6),
        Text(install ? t.addToHomeFirst : t.notificationsWhy, style: const TextStyle(color: AppColors.body, height: 1.45)),
        const SizedBox(height: 12),
        Row(children: [
          if (!install)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _push.busy ? null : _turnOn,
              child: Text(t.turnOn),
            ),
          if (!install) const SizedBox(width: 8),
          TextButton(onPressed: _dismiss, child: Text(t.notNow)),
        ]),
      ]),
    );
  }
}

/// "How was it?" with five stars to tap, after a slot you attended.
class _RateCard extends StatelessWidget {
  const _RateCard({required this.booking, required this.onRate});
  final Booking booking;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = booking.slot!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.howWasIt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.body)),
        const SizedBox(height: 4),
        Row(children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: t.starsOutOf5('$i'),
              visualDensity: VisualDensity.compact,
              onPressed: () => onRate(i),
              icon: const Icon(Icons.star_outline_rounded, size: 32, color: Stars.gold),
            ),
        ]),
      ]),
    );
  }
}
