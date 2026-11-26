import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/booking_review_sheet.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

class _Data {
  _Data(this.slot, this.booking, this.feePercent);
  final Slot? slot;
  final Booking? booking;
  final int feePercent;
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
    ]);
    return _Data(results[0] as Slot?, results[1] as Booking?, results[2] as int);
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
      showMessage(context, AppLocalizations.of(context).requestSent);
      _reload();
    }
  }

  Future<void> _cancel(Booking b, SlotKind kind) async {
    final t = AppLocalizations.of(context);
    final label = kind == SlotKind.cover ? t.cancelOffer : t.cancelBooking;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(label)),
        ],
      ),
    );
    if (ok != true) return;
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

        return Scaffold(
          appBar: AppBar(),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (slot.photoPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(repo.photoUrl(slot.photoPath!), fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Container(color: ks.tint)),
                  ),
                ),
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
                    Row(children: [
                      CircleAvatar(
                        backgroundColor: AppColors.ink,
                        foregroundColor: Colors.white,
                        child: Text(initials(slot.hostName), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(slot.hostName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          Row(children: [
                            const Icon(Icons.verified, size: 15, color: AppColors.nile),
                            const SizedBox(width: 4),
                            Text(t.syndicateChecked, style: const TextStyle(fontSize: 13, color: AppColors.body)),
                          ]),
                        ]),
                      ),
                    ]),
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
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _actions(context, slot, booking, isHost, snap.data!.feePercent),
          ),
        );
      },
    );
  }

  Widget _actions(BuildContext context, Slot slot, Booking? booking, bool isHost, int feePercent) {
    final t = AppLocalizations.of(context);
    if (isHost) {
      return FilledButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ManageSlotScreen(slotId: slot.id)));
          _reload();
        },
        child: Text(t.manageRequests),
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
    final blockedReason = slot.isFull ? t.errSlotFull : roleMismatch ? t.errRoleMismatch : null;
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
