import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// The host's view of one slot: who asked, accept or decline, open or close it.
class ManageSlotScreen extends StatefulWidget {
  const ManageSlotScreen({super.key, required this.slotId});
  final String slotId;

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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.requests, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<(Slot?, List<SlotRequest>)>(
        future: _data,
        builder: (context, snap) {
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
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(t.takingRequests, style: const TextStyle(fontWeight: FontWeight.w700)),
                  value: slot.isOpen,
                  onChanged: _setOpen,
                ),
                const Divider(),
                if (requests.isEmpty) EmptyView(text: t.noRequestsYet),
                for (final r in requests) _RequestTile(
                  request: r,
                  busy: _busyId == r.id,
                  onAccept: () => _respond(r, true),
                  onDecline: () => _respond(r, false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.busy, required this.onAccept, required this.onDecline});
  final SlotRequest request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = request;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: AppColors.nileTint,
            foregroundColor: AppColors.nile,
            child: Text(initials(r.fullName), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(roleName(t, r.role), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ]),
          ),
          StatusChip(status: r.status),
        ]),
        if (r.message.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(r.message, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.body)),
        ],
        if (r.status == BookingStatus.pending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton(onPressed: busy ? null : onAccept, child: Text(t.accept))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: busy ? null : onDecline, child: Text(t.decline))),
          ]),
        ],
        if (r.status == BookingStatus.accepted && r.phone != null) ...[
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
      ]),
    );
  }
}
