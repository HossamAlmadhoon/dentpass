import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/notifications_screen.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

enum _Filter { all, learn, rent, cover }

List<SlotKind>? _kindsFor(_Filter f) => switch (f) {
      _Filter.all => null,
      _Filter.learn => const [SlotKind.observe, SlotKind.course],
      _Filter.rent => const [SlotKind.rent],
      _Filter.cover => const [SlotKind.cover],
    };

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.profile, required this.onPostSlot});
  final Profile profile;
  final VoidCallback onPostSlot;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  _Filter _filter = _Filter.all;
  String? _area;
  late Future<List<Slot>> _slots;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() {
    _slots = repo.feed(kinds: _kindsFor(_filter), area: _area);
    repo.unreadCount().then((n) {
      if (mounted) setState(() => _unread = n);
    }).catchError((_) {});
  }

  void _load() => setState(_fetch);

  Future<void> _openSlot(Slot s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SlotDetailScreen(slotId: s.id, profile: widget.profile)),
    );
    _load();
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotificationsScreen(profile: widget.profile)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final labels = {
      _Filter.all: t.filterAll,
      _Filter.learn: t.filterLearn,
      _Filter.rent: t.filterRent,
      _Filter.cover: t.filterCover,
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.verified_outlined, color: AppColors.nile),
          const SizedBox(width: 8),
          Text(t.appName, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(
            tooltip: t.notifications,
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(t.exploreTitle,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
            ),
            const SizedBox(height: 14),
            SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: [for (final f in _Filter.values) ButtonSegment(value: f, label: Text(labels[f]!))],
              selected: {_filter},
              onSelectionChanged: (s) {
                _filter = s.first;
                _load();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _area,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.place_outlined),
                labelText: t.area,
                isDense: true,
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(t.allAreas)),
                for (final a in areaKeys) DropdownMenuItem<String?>(value: a, child: Text(areaName(context, a))),
              ],
              onChanged: (v) {
                _area = v;
                _load();
              },
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<Slot>>(
              future: _slots,
              builder: (context, snap) {
                if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _load);
                if (!snap.hasData) {
                  return const Padding(padding: EdgeInsets.all(48), child: LoadingView());
                }
                final slots = snap.data!;
                if (slots.isEmpty) {
                  return EmptyView(text: t.emptyFeed, actionLabel: t.emptyFeedAction, onAction: widget.onPostSlot);
                }
                return Column(
                  children: [
                    for (final s in slots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SlotCard(slot: s, onTap: () => _openSlot(s)),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
