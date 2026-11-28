import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/screens/review_sheet.dart';
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
  late Future<(List<Booking>, Set<String>)> _items = _fetch();

  Future<(List<Booking>, Set<String>)> _fetch() async {
    final results = await Future.wait([repo.myBookings(), repo.myRatedBookingIds()]);
    return (results[0] as List<Booking>, results[1] as Set<String>);
  }

  void _reload() => setState(() => _items = _fetch());

  Widget _trailing(Booking b, Set<String> rated) {
    final t = AppLocalizations.of(context);
    final ended = b.slot!.hasEnded;
    if (b.status == BookingStatus.accepted && ended && !rated.contains(b.id)) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
          onPressed: () async {
            if (await showReviewSheet(context, bookingId: b.id, title: t.rateHost)) _reload();
          },
          icon: const Icon(Icons.star_rounded, color: Color(0xFFB7791F), size: 20),
          label: Text(t.rateHost),
        ),
      );
    }
    if (b.status == BookingStatus.accepted && ended) {
      return Text(t.rated, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.nile));
    }
    if (b.status == BookingStatus.accepted && b.paidAt == null && b.slot!.kind != SlotKind.cover && b.totalEgp > 0) {
      return Text(t.paymentDue(priceText(context, b.totalEgp)),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.amber));
    }
    return Align(alignment: AlignmentDirectional.centerStart, child: StatusChip(status: b.status));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<(List<Booking>, Set<String>)>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        final (all, rated) = snap.data!;
        final items = all.where((b) => b.slot != null).toList();
        // Coming up (soonest first), then everything else (latest first)
        final upcoming = items.where((b) => b.isActive && !b.slot!.hasEnded).toList()
          ..sort((a, b) => a.slot!.startsAt.compareTo(b.slot!.startsAt));
        final past = items.where((b) => !upcoming.contains(b)).toList()
          ..sort((a, b) => b.slot!.startsAt.compareTo(a.slot!.startsAt));
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty) EmptyView(text: t.noBookings),
              for (final (title, list) in [(t.upcoming, upcoming), (t.past, past)])
                if (list.isNotEmpty) ...[
                  ListHeading(title),
                  for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SlotCard(
                    slot: b.slot!,
                    trailing: _trailing(b, rated),
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
        final upcoming = items.where((h) => !h.slot.hasEnded).toList()
          ..sort((a, b) => a.slot.startsAt.compareTo(b.slot.startsAt));
        final past = items.where((h) => h.slot.hasEnded).toList()
          ..sort((a, b) => b.slot.startsAt.compareTo(a.slot.startsAt));
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty) EmptyView(text: t.noPosts),
              for (final (title, list) in [(t.upcoming, upcoming), (t.past, past)])
                if (list.isNotEmpty) ...[
                  ListHeading(title),
                  for (final h in list)
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
                        MaterialPageRoute(builder: (_) => ManageSlotScreen(slotId: h.slot.id, profile: widget.profile)),
                      );
                      _reload();
                    },
                  ),
                ),
                ],
            ],
          ),
        );
      },
    );
  }
}
