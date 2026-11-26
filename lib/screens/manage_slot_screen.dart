import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/member_screen.dart';
import 'package:dentpass/screens/post_slot_screen.dart';
import 'package:dentpass/screens/review_sheet.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// The host's view of one slot: who asked, accept or decline, edit, close or delete it,
/// and rate people afterwards.
class ManageSlotScreen extends StatefulWidget {
  const ManageSlotScreen({super.key, required this.slotId, required this.profile});
  final String slotId;
  final Profile profile;

  @override
  State<ManageSlotScreen> createState() => _ManageSlotScreenState();
}

class _ManageSlotScreenState extends State<ManageSlotScreen> {
  late Future<(Slot?, List<SlotRequest>)> _data = _fetch();
  String? _busyId;

  Future<(Slot?, List<SlotRequest>)> _fetch() async {
    final slot = await repo.slot(widget.slotId);
    final requests = await repo.slotRequests(widget.slotId);
    return (slot, requests);
  }

  void _reload() => setState(() => _data = _fetch());

  Future<void> _respond(SlotRequest r, bool accept) async {
    setState(() => _busyId = r.id);
    try {
      await repo.respond(r.id, accept);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _setOpen(bool open) async {
    try {
      await repo.setSlotOpen(widget.slotId, open);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  Future<void> _edit(Slot slot) async {
    final t = AppLocalizations.of(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PostSlotScreen(
          existing: slot,
          onPosted: (_) {
            Navigator.pop(ctx);
            showMessage(context, t.changesSaved);
          },
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _duplicate(Slot slot) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PostSlotScreen(
          template: slot,
          onPosted: (id) => Navigator.pushReplacement(
            ctx,
            MaterialPageRoute(builder: (_) => ManageSlotScreen(slotId: id, profile: widget.profile)),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Slot slot) async {
    final t = AppLocalizations.of(context);
    if (!await confirmAction(context, title: t.deleteSlot, body: t.deleteSlotConfirm, action: t.delete, danger: true)) {
      return;
    }
    try {
      await repo.deleteSlot(slot.id, photoPaths: slot.photoPaths);
      if (!mounted) return;
      showMessage(context, t.slotDeleted);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<(Slot?, List<SlotRequest>)>(
      future: _data,
      builder: (context, snap) {
        final slot = snap.data?.$1;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.requests, style: const TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              if (slot != null) ...[
                IconButton(tooltip: t.editSlot, onPressed: () => _edit(slot), icon: const Icon(Icons.edit_outlined)),
                IconButton(tooltip: t.duplicate, onPressed: () => _duplicate(slot), icon: const Icon(Icons.copy_all_outlined)),
                IconButton(tooltip: t.deleteSlot, onPressed: () => _delete(slot), icon: const Icon(Icons.delete_outline)),
              ],
            ],
          ),
          body: Builder(builder: (context) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const LoadingView();
            final (slot, requests) = snap.data!;
            if (slot == null) return EmptyView(text: t.errSlotClosed);
            final ks = kindStyle(slot.kind);

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: ks.tint, borderRadius: BorderRadius.circular(18)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(kindName(t, slot.kind), style: TextStyle(fontWeight: FontWeight.w700, color: ks.ink)),
                      const SizedBox(height: 4),
                      Text(slot.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(whenText(context, slot.startsAt, slot.endsAt), style: const TextStyle(color: AppColors.body)),
                      if (slot.kind != SlotKind.cover) ...[
                        const SizedBox(height: 4),
                        Text(availabilityText(t, slot), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (!slot.hasEnded)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(t.takingRequests, style: const TextStyle(fontWeight: FontWeight.w700)),
                      value: slot.isOpen,
                      onChanged: _setOpen,
                    ),
                  const Divider(),
                  if (requests.isEmpty) EmptyView(text: t.noRequestsYet),
                  for (final r in requests)
                    _RequestTile(
                      request: r,
                      slotEnded: slot.hasEnded,
                      busy: _busyId == r.id,
                      onAccept: () => _respond(r, true),
                      onDecline: () => _respond(r, false),
                      onOpen: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => MemberScreen(userId: r.userId, viewer: widget.profile)),
                      ),
                      onRate: () async {
                        if (await showReviewSheet(context, bookingId: r.id, title: t.rateMember(r.fullName))) _reload();
                      },
                    ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.slotEnded,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
    required this.onRate,
  });
  final SlotRequest request;
  final bool slotEnded;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpen;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = request;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Row(children: [
            Avatar(name: r.fullName, photoUrl: null, dark: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Row(children: [
                  Text(roleName(t, r.role), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  const SizedBox(width: 8),
                  RatingLine(rating: r.rating, count: r.reviews, compact: true),
                ]),
              ]),
            ),
            StatusChip(status: r.status),
          ]),
        ),
        if (r.message.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(r.message, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.body)),
        ],
        if (r.status == BookingStatus.pending && !slotEnded) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton(onPressed: busy ? null : onAccept, child: Text(t.accept))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: busy ? null : onDecline, child: Text(t.decline))),
          ]),
        ],
        if (r.status == BookingStatus.accepted && r.phone != null && !slotEnded) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => callNumber(r.phone!),
                icon: const Icon(Icons.call_outlined),
                label: Text(t.call),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openWhatsApp(r.phone!),
                icon: const Icon(Icons.chat_outlined),
                label: Text(t.whatsapp),
              ),
            ),
          ]),
        ],
        if (r.status == BookingStatus.accepted && slotEnded) ...[
          const SizedBox(height: 12),
          r.reviewed
              ? Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.nile, size: 20),
                  const SizedBox(width: 6),
                  Text(t.rated, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.nile)),
                ])
              : OutlinedButton.icon(
                  onPressed: onRate,
                  icon: const Icon(Icons.star_rounded, color: Color(0xFFB7791F)),
                  label: Text(t.rateMember(r.fullName)),
                ),
        ],
      ]),
    );
  }
}
