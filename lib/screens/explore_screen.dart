import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/home_header.dart';
import 'package:dentpass/screens/notifications_screen.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/screens/verify_gate.dart';
import 'package:dentpass/services/location.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/feedback.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/maps.dart';
import 'package:dentpass/ui/widgets.dart';

enum _Filter { all, learn, rent, cover }

enum _When { any, week, weekend, day }

List<SlotKind>? _kindsFor(_Filter f) => switch (f) {
      _Filter.all => null,
      _Filter.learn => const [SlotKind.observe, SlotKind.course],
      _Filter.rent => const [SlotKind.rent],
      _Filter.cover => const [SlotKind.cover],
    };

/// The coming Friday and Saturday (the weekend in Egypt), or this one if it has started.
(DateTime, DateTime) _weekend(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final start = now.weekday == DateTime.saturday
      ? today.subtract(const Duration(days: 1))
      : today.add(Duration(days: (DateTime.friday - now.weekday) % 7));
  return (start, start.add(const Duration(days: 2)));
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.profile, required this.onPostSlot, this.onProfileChanged});
  final Profile profile;
  final VoidCallback onPostSlot;

  /// Reloads the member's profile, for example after sending papers.
  final VoidCallback? onProfileChanged;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  _When _when = _When.any;
  DateTime? _day;
  String? _area;
  bool _showMap = false;
  bool _nearMe = false;
  LatLng? _me;
  late Future<List<Slot>> _slots;
  int _unread = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) _range() {
    final now = DateTime.now();
    return switch (_when) {
      _When.any => (null, null),
      _When.week => (now, now.add(const Duration(days: 7))),
      _When.weekend => _weekend(now),
      _When.day => _day == null ? (null, null) : (_day!, _day!.add(const Duration(days: 1))),
    };
  }

  void _fetch() {
    final (from, to) = _range();
    _slots = repo.feed(kinds: _kindsFor(_filter), area: _area, query: _search.text, from: from, to: to);
    repo.unreadCount().then((n) {
      if (mounted) setState(() => _unread = n);
    }).catchError((_) {});
  }

  void _load() => setState(() {
        _refreshKey++;
        _fetch();
      });

  Future<void> _saveAlert() async {
    final t = AppLocalizations.of(context);
    try {
      await repo.addAlert(kinds: _kindsFor(_filter), area: _area);
      if (mounted) showMessage(context, t.alertSaved);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  Future<void> _chooseDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;
    _day = d;
    _when = _When.day;
    _load();
  }

  Future<void> _toggleNearMe() async {
    if (_nearMe) {
      setState(() => _nearMe = false);
      return;
    }
    final here = await currentLocation();
    if (!mounted) return;
    if (here == null) {
      showMessage(context, AppLocalizations.of(context).locationDenied);
      return;
    }
    setState(() {
      _me = here;
      _nearMe = true;
    });
  }

  double? _distance(Slot s) =>
      (_nearMe && _me != null && s.hasLocation) ? distanceKm(_me!, LatLng(s.lat!, s.lng!)) : null;

  List<Slot> _sorted(List<Slot> slots) {
    if (!_nearMe || _me == null) return slots;
    final list = [...slots];
    list.sort((a, b) => (_distance(a) ?? double.infinity).compareTo(_distance(b) ?? double.infinity));
    return list;
  }

  Future<void> _openSlot(Slot s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SlotDetailScreen(slotId: s.id, profile: widget.profile)),
    );
    if (mounted) _load();
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotificationsScreen(profile: widget.profile)),
    );
    if (mounted) _load();
  }

  void _showPinned(Slot s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SlotCard(
            slot: s,
            distanceKm: _distance(s),
            onTap: () {
              Navigator.pop(ctx);
              _openSlot(s);
            },
          ),
        ),
      ),
    );
  }

  Widget _filters(AppLocalizations t) {
    final labels = {
      _Filter.all: t.filterAll,
      _Filter.learn: t.filterLearn,
      _Filter.rent: t.filterRent,
      _Filter.cover: t.filterCover,
    };
    Widget chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FilterChip(
            avatar: icon == null ? null : Icon(icon, size: 18),
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: t.search,
          isDense: true,
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: t.cancel,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _load(),
      ),
      const SizedBox(height: 10),
      SegmentedButton<_Filter>(
        showSelectedIcon: false,
        segments: [for (final f in _Filter.values) ButtonSegment(value: f, label: Text(labels[f]!))],
        selected: {_filter},
        onSelectionChanged: (s) {
          _filter = s.first;
          _load();
        },
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          chip(t.nearMe, _nearMe, _toggleNearMe, icon: Icons.near_me_outlined),
          chip(t.anyTime, _when == _When.any, () {
            _when = _When.any;
            _load();
          }),
          chip(t.thisWeek, _when == _When.week, () {
            _when = _When.week;
            _load();
          }),
          chip(t.weekend, _when == _When.weekend, () {
            _when = _When.weekend;
            _load();
          }),
          chip(_when == _When.day && _day != null ? fullDate(context, _day!) : t.pickDate, _when == _When.day, _chooseDay,
              icon: Icons.calendar_today_outlined),
        ]),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        initialValue: _area,
        decoration: InputDecoration(prefixIcon: const Icon(Icons.place_outlined), labelText: t.area, isDense: true),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(t.allAreas)),
          for (final a in areaKeys) DropdownMenuItem<String?>(value: a, child: Text(areaName(context, a))),
        ],
        onChanged: (v) {
          _area = v;
          _load();
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.verified_outlined, color: AppColors.nile),
          const SizedBox(width: 8),
          Text(t.appName, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(
            tooltip: t.alertMe,
            onPressed: _saveAlert,
            icon: const Icon(Icons.notification_add_outlined),
          ),
          IconButton(
            tooltip: _showMap ? t.showList : t.showMap,
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: Icon(_showMap ? Icons.view_list_outlined : Icons.map_outlined),
          ),
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
      body: FutureBuilder<List<Slot>>(
        future: _slots,
        builder: (context, snap) {
          final slots = snap.hasData ? _sorted(snap.data!) : const <Slot>[];

          if (_showMap) {
            return Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: _filters(t)),
              Expanded(
                child: snap.hasError
                    ? ErrorView(error: snap.error!, onRetry: _load)
                    : !snap.hasData
                        ? const LoadingView()
                        : Stack(children: [
                            SlotsMap(slots: slots, me: _nearMe ? _me : null, onSelect: _showPinned),
                            if (!slots.any((s) => s.hasLocation))
                              Positioned(
                                left: 16,
                                right: 16,
                                top: 12,
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(t.noPinsHere, textAlign: TextAlign.center),
                                  ),
                                ),
                              ),
                          ]),
              ),
            ]);
          }

          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                HomeHeader(profile: widget.profile, refreshKey: _refreshKey),
                VerifyBanner(profile: widget.profile, onChanged: widget.onProfileChanged ?? () {}),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(t.exploreTitle, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
                ),
                const SizedBox(height: 12),
                _filters(t),
                const SizedBox(height: 14),
                if (snap.hasError)
                  ErrorView(error: snap.error!, onRetry: _load)
                else if (!snap.hasData)
                  const SkeletonList()
                else if (slots.isEmpty)
                  EmptyView(text: t.emptyFeed, actionLabel: t.emptyFeedAction, onAction: widget.onPostSlot)
                else
                  for (final s in slots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SlotCard(slot: s, distanceKm: _distance(s), onTap: () => _openSlot(s)),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
