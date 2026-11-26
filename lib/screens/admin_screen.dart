import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// Admin area: new members to check, all members, all upcoming slots, and the numbers.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.reviewMembers, style: const TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t.adminWaiting),
              Tab(text: t.adminMembers),
              Tab(text: t.adminSlots),
              Tab(text: t.adminOverview),
            ],
          ),
        ),
        body: const TabBarView(children: [_Waiting(), _Members(), _Slots(), _Overview()]),
      ),
    );
  }
}

/// Owns its text field, so the field is cleaned up only after the dialog has closed.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});
  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(controller: _controller, autofocus: true, maxLength: 300, maxLines: 3),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(t.send),
        ),
      ],
    );
  }
}

Future<String?> _askReason(BuildContext context, String title) =>
    showDialog<String>(context: context, builder: (_) => _ReasonDialog(title: title));

String _memberLine(BuildContext context, Profile p) {
  final t = AppLocalizations.of(context);
  return [roleName(t, p.role), areaName(context, p.area)].where((s) => s.isNotEmpty).join(' · ');
}

// ------------------------------------------------------------------ waiting
class _Waiting extends StatefulWidget {
  const _Waiting();

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  late Future<List<Profile>> _items = repo.pendingMembers();

  void _reload() => setState(() => _items = repo.pendingMembers());

  Future<void> _decide(Profile p, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _askReason(context, AppLocalizations.of(context).rejectReason);
      if (reason == null) return;
    }
    try {
      await repo.setVerification(p.id, approve, reason: reason);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<Profile>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        final items = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty) EmptyView(text: t.noPending),
              for (final p in items)
                Card(
                  color: Colors.white,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(_memberLine(context, p), style: const TextStyle(color: AppColors.muted)),
                      if (p.syndicateNo != null) Text('${t.syndicateNo}: ${p.syndicateNo}'),
                      if (p.phone != null) Text('${t.phone}: ${p.phone}', textDirection: TextDirection.ltr),
                      const SizedBox(height: 12),
                      Row(children: [
                        if (p.cardPath != null) Expanded(child: _DocImage(label: t.syndicateCard, path: p.cardPath!)),
                        if (p.cardPath != null) const SizedBox(width: 10),
                        if (p.idPath != null) Expanded(child: _DocImage(label: t.nationalId, path: p.idPath!)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: FilledButton(onPressed: () => _decide(p, true), child: Text(t.approve))),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton(onPressed: () => _decide(p, false), child: Text(t.reject))),
                      ]),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DocImage extends StatelessWidget {
  const _DocImage({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: FutureBuilder<String>(
            future: repo.verificationFileUrl(path),
            builder: (context, snap) {
              if (!snap.hasData) return Container(color: AppColors.track);
              return InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(snap.data!))),
                ),
                child: Image.network(snap.data!, fit: BoxFit.cover),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ members
class _Members extends StatefulWidget {
  const _Members();

  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  final _search = TextEditingController();
  VerificationStatus _status = VerificationStatus.approved;
  late Future<List<Profile>> _items = _fetch();

  Future<List<Profile>> _fetch() => repo.members(status: _status, query: _search.text);

  void _reload() => setState(() => _items = _fetch());

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(Profile p) async {
    final t = AppLocalizations.of(context);
    final suspend = p.status == VerificationStatus.approved;
    String? reason;
    if (suspend) {
      reason = await _askReason(context, t.suspendReason);
      if (reason == null) return;
    }
    try {
      await repo.setMemberStatus(p.id, suspend: suspend, reason: reason);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final filters = {
      VerificationStatus.approved: t.statusApproved,
      VerificationStatus.suspended: t.statusSuspended,
      VerificationStatus.rejected: t.statusRejected,
    };
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchMembers, isDense: true),
          onSubmitted: (_) => _reload(),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final e in filters.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _status == e.key,
                  onSelected: (_) {
                    _status = e.key;
                    _reload();
                  },
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Profile>>(
          future: _items,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const LoadingView();
            final items = snap.data!;
            if (items.isEmpty) return EmptyView(text: t.noMembers);
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, i) => const Divider(),
                itemBuilder: (context, i) {
                  final p = items[i];
                  final canToggle = !p.isAdmin &&
                      (p.status == VerificationStatus.approved || p.status == VerificationStatus.suspended);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Avatar(name: p.fullName, photoUrl: p.avatarPath == null ? null : repo.avatarUrl(p.avatarPath!), dark: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(_memberLine(context, p), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                          if (p.phone != null)
                            Text(p.phone!, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                          if ((p.rejectionReason ?? '').isNotEmpty)
                            Text(p.rejectionReason!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
                        ]),
                      ),
                      if (canToggle)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                          onPressed: () => _toggle(p),
                          child: Text(p.status == VerificationStatus.approved ? t.suspend : t.reinstate),
                        ),
                    ]),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ slots
class _Slots extends StatefulWidget {
  const _Slots();

  @override
  State<_Slots> createState() => _SlotsState();
}

class _SlotsState extends State<_Slots> {
  late Future<List<Slot>> _items = repo.adminSlots();

  void _reload() => setState(() => _items = repo.adminSlots());

  Future<void> _remove(Slot s) async {
    final t = AppLocalizations.of(context);
    if (!await confirmAction(context, title: t.removeSlot, body: t.deleteSlotConfirm, action: t.delete, danger: true)) {
      return;
    }
    try {
      await repo.deleteSlot(s.id);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<Slot>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        final items = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty) EmptyView(text: t.noOpenSlots),
              for (final s in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SlotCard(
                    slot: s,
                    onTap: () {},
                    trailing: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                        ),
                        onPressed: () => _remove(s),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(t.removeSlot),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ overview
class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late Future<AdminOverview> _data = repo.adminOverview();

  void _reload() => setState(() => _data = repo.adminOverview());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<AdminOverview>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        final o = snap.data!;
        final rows = [
          (t.ovMembers, o.count('members')),
          (t.ovWaiting, o.count('waiting')),
          (t.statusSuspended, o.count('suspended')),
          (t.ovOpenSlots, o.count('open_slots')),
          (t.ovBookings, o.count('bookings_30d')),
          (t.ovAccepted, o.count('accepted_30d')),
          (t.ovFees, o.count('fees_30d')),
        ];
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  for (final (label, value) in rows)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: label == rows.last.$1 ? null : const Border(bottom: BorderSide(color: AppColors.line)),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
                        Text(money(context, value), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
