import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/booking_review_sheet.dart';
import 'package:dentpass/screens/info_screens.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/screens/member_screen.dart';
import 'package:dentpass/screens/review_sheet.dart';
import 'package:dentpass/services/calendar.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/feedback.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/maps.dart';
import 'package:dentpass/ui/widgets.dart';

class _Data {
  _Data(this.slot, this.booking, this.feePercent, this.rated);
  final Slot? slot;
  final Booking? booking;
  final int feePercent;
  final bool rated;
}

class SlotDetailScreen extends StatefulWidget {
  const SlotDetailScreen({super.key, required this.slotId, required this.profile});
  final String slotId;
  final Profile profile;

  @override
  State<SlotDetailScreen> createState() => _SlotDetailScreenState();
}

class _SlotDetailScreenState extends State<SlotDetailScreen> {
  late Future<_Data> _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = _fetch();
  }

  Future<_Data> _fetch() async {
    final results = await Future.wait([
      repo.slot(widget.slotId),
      repo.myBookingFor(widget.slotId),
      repo.feePercent(),
      repo.myRatedBookingIds(),
    ]);
    final booking = results[1] as Booking?;
    final rated = results[3] as Set<String>;
    return _Data(results[0] as Slot?, booking, results[2] as int, booking != null && rated.contains(booking.id));
  }

  void _reload() => setState(() => _data = _fetch());

  Future<void> _book(Slot slot, int feePercent) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BookingReviewSheet(slot: slot, feePercent: feePercent),
    );
    if (sent == true && mounted) {
      final t = AppLocalizations.of(context);
      _reload();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => DoneScreen(
            title: slot.kind == SlotKind.cover ? t.statusPending : t.requestSentTitle,
            body: t.requestSentBody(slot.hostName),
            primaryLabel: t.backToExplore,
            onPrimary: () => Navigator.of(ctx)..pop()..pop(),
            secondaryLabel: t.viewSlot,
            onSecondary: () => Navigator.pop(ctx),
          ),
        ),
      );
    }
  }

  Future<void> _addToCalendar(Slot slot) async {
    final t = AppLocalizations.of(context);
    final location = [slot.address, areaName(context, slot.area)].where((s) => s.isNotEmpty).join(', ');
    final details = '${kindName(t, slot.kind)} · ${slot.hostName}';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(t.phoneCalendar),
            onTap: () {
              Navigator.pop(ctx);
              openPhoneCalendar(buildIcs(
                id: slot.id, title: slot.title, start: slot.startsAt, end: slot.endsAt, location: location, details: details,
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(t.googleCalendar),
            onTap: () {
              Navigator.pop(ctx);
              openGoogleCalendar(title: slot.title, start: slot.startsAt, end: slot.endsAt, location: location, details: details);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _cancel(Booking b, SlotKind kind) async {
    final t = AppLocalizations.of(context);
    final label = kind == SlotKind.cover ? t.cancelOffer : t.cancelBooking;
    if (!await confirmAction(context, title: label, action: label)) return;
    setState(() => _busy = true);
    try {
      await repo.cancelBooking(b.id);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openHost(Slot slot) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MemberScreen(userId: slot.hostId, viewer: widget.profile)),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<_Data>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(appBar: AppBar(), body: ErrorView(error: snap.error!, onRetry: _reload));
        if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const LoadingView());
        final slot = snap.data!.slot;
        if (slot == null) return Scaffold(appBar: AppBar(), body: EmptyView(text: t.errSlotClosed));
        final booking = snap.data!.booking;
        final ks = kindStyle(slot.kind);
        final isHost = slot.hostId == widget.profile.id;

        final going = isHost || booking?.status == BookingStatus.accepted;
        return Scaffold(
          appBar: AppBar(actions: [
            if (going && !slot.hasEnded)
              IconButton(
                tooltip: t.addToCalendar,
                onPressed: () => _addToCalendar(slot),
                icon: const Icon(Icons.event_available_outlined),
              ),
            if (!isHost)
              PopupMenuButton<String>(
                onSelected: (_) => showReportSheet(context, slotId: slot.id, memberId: slot.hostId, title: t.reportSlot),
                itemBuilder: (_) => [PopupMenuItem(value: 'report', child: Text(t.reportSlot))],
              ),
          ]),
          body: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (slot.photoPaths.isNotEmpty) ...[
                  PhotoGallery(urls: [for (final p in slot.photoPaths) repo.photoUrl(p)], tint: ks.tint),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: ks.tint, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(ks.icon, size: 18, color: ks.ink),
                        const SizedBox(width: 6),
                        Text(kindName(t, slot.kind),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ks.ink)),
                      ]),
                      const SizedBox(height: 6),
                      Text(slot.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openHost(slot),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Avatar(name: slot.hostName, photoUrl: null),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(slot.hostName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                Row(children: [
                                  const Icon(Icons.verified, size: 15, color: AppColors.nile),
                                  const SizedBox(width: 4),
                                  Text(t.syndicateChecked, style: const TextStyle(fontSize: 13, color: AppColors.body)),
                                  const SizedBox(width: 10),
                                  RatingLine(rating: slot.hostRating, count: slot.hostReviews, compact: true),
                                ]),
                              ]),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.muted),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FactRow(label: t.when, value: whenText(context, slot.startsAt, slot.endsAt)),
                      FactRow(
                        label: t.where,
                        value: slot.address.isNotEmpty
                            ? '${areaName(context, slot.area)}\n${slot.address}'
                            : '${areaName(context, slot.area)}\n${t.addressAfterAccept}',
                      ),
                      FactRow(
                        label: slot.kind == SlotKind.cover ? t.pay : t.price,
                        value: priceText(context, slot.priceEgp),
                      ),
                      FactRow(
                        label: t.places,
                        value: slot.kind == SlotKind.cover && slot.needRole != null
                            ? t.needRoleLine(roleName(t, slot.needRole!))
                            : availabilityText(t, slot),
                      ),
                      if (slot.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(slot.description, style: const TextStyle(fontSize: 15, height: 1.6, color: AppColors.body)),
                      ],
                      if (slot.hasLocation) ...[
                        const SizedBox(height: 18),
                        SlotMiniMap(slot: slot),
                      ],
                      if (slot.hostPhone != null) ...[
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => callNumber(slot.hostPhone!),
                              icon: const Icon(Icons.call_outlined),
                              label: Text(t.callHost),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => openWhatsApp(slot.hostPhone!),
                              icon: const Icon(Icons.chat_outlined),
                              label: Text(t.whatsapp),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _actions(context, slot, booking, isHost, snap.data!.feePercent, snap.data!.rated),
          ),
        );
      },
    );
  }

  Widget _actions(BuildContext context, Slot slot, Booking? booking, bool isHost, int feePercent, bool rated) {
    final t = AppLocalizations.of(context);
    if (isHost) {
      return FilledButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ManageSlotScreen(slotId: slot.id, profile: widget.profile)),
          );
          if (mounted) _reload();
        },
        child: Text(t.manageRequests),
      );
    }
    // After the slot: rate the host
    if (booking != null && booking.status == BookingStatus.accepted && slot.hasEnded) {
      return rated
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle, color: AppColors.nile),
              const SizedBox(width: 6),
              Text(t.rated, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.nile)),
            ])
          : FilledButton.icon(
              onPressed: () async {
                if (await showReviewSheet(context, bookingId: booking.id, title: t.rateHost)) _reload();
              },
              icon: const Icon(Icons.star_rounded),
              label: Text(t.rateHost),
            );
    }
    if (booking != null && booking.isActive) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        StatusChip(status: booking.status),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _busy ? null : () => _cancel(booking, slot.kind),
          child: Text(slot.kind == SlotKind.cover ? t.cancelOffer : t.cancelBooking),
        ),
      ]);
    }
    final roleMismatch = slot.kind == SlotKind.cover && slot.needRole != null && slot.needRole != widget.profile.role;
    final blockedReason = !slot.isOpen || slot.hasEnded
        ? t.errSlotClosed
        : slot.isFull
            ? t.errSlotFull
            : roleMismatch
                ? t.errRoleMismatch
                : null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (blockedReason != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(blockedReason, style: const TextStyle(color: AppColors.body)),
        ),
      FilledButton(
        onPressed: blockedReason == null ? () => _book(slot, feePercent) : null,
        child: Text(actionLabel(t, slot.kind)),
      ),
    ]);
  }
}
