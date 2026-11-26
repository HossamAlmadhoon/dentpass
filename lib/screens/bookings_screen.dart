import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

/// What you booked, and what you posted.
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key, required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.tabBookings, style: const TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(tabs: [Tab(text: t.myBookings), Tab(text: t.myPosts)]),
        ),
        body: TabBarView(children: [_MyBookings(profile: profile), _MyPosts(profile: profile)]),
      ),
    );
  }
}

class _MyBookings extends StatefulWidget {
  const _MyBookings({required this.profile});
  final Profile profile;

  @override
  State<_MyBookings> createState() => _MyBookingsState();
}

class _MyBookingsState extends State<_MyBookings> {
  late Future<List<Booking>> _items = repo.myBookings();

  void _reload() => setState(() => _items = repo.myBookings());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<Booking>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        final items = snap.data!.where((b) => b.slot != null).toList();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty) EmptyView(text: t.noBookings),
              for (final b in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SlotCard(
                    slot: b.slot!,
                    trailing: Align(alignment: AlignmentDirectional.centerStart, child: StatusChip(status: b.status)),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SlotDetailScreen(slotId: b.slotId, profile: widget.profile)),
                      );
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MyPosts extends StatefulWidget {
  const _MyPosts({required this.profile});
  final Profile profile;

  @override
  State<_MyPosts> createState() => _MyPostsState();
}

class _MyPostsState extends State<_MyPosts> {
  late Future<List<HostedSlot>> _items = repo.myPosts();

  void _reload() => setState(() => _items = repo.myPosts());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<HostedSlot>>(
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
              if (items.isEmpty) EmptyView(text: t.noPosts),
              for (final h in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SlotCard(
                    slot: h.slot,
                    trailing: Text(
                      !h.slot.isOpen
                          ? t.closed
                          : h.pendingCount > 0
                              ? t.newRequests(h.pendingCount)
                              : h.totalCount == 0
                                  ? t.noRequestsYet
                                  : t.takingRequests,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: h.pendingCount > 0 ? AppColors.amber : AppColors.body,
                      ),
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ManageSlotScreen(slotId: h.slot.id)),
                      );
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
