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

  /// How many filters are on besides the type: place, time, near me.
  int get _extraFilters => (_nearMe ? 1 : 0) + (_when != _When.any ? 1 : 0) + (_area != null ? 1 : 0);

  void _clearFilters() {
    _nearMe = false;
    _when = _When.any;
    _day = null;
    _area = null;
    _load();
  }

  /// Time, area and "near me" live in a sheet, so the slots stay on the first screen.
  Future<void> _openFilters() async {
    final t = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void change(VoidCallback f) {
            f();
            setSheet(() {});
            _load();
          }

          Widget whenChip(String label, _When w, {VoidCallback? onTap, IconData? icon}) => ChoiceChip(
                avatar: icon == null ? null : Icon(icon, size: 18),
                label: Text(label),
                selected: _when == w,
                showCheckmark: false,
                onSelected: (_) => onTap != null ? onTap() : change(() => _when = w),
              );

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(t.filters, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                  if (_extraFilters > 0)
                    TextButton(onPressed: () => change(_clearFilters), child: Text(t.clearFilters)),
                ]),
                const SizedBox(height: 12),
                SectionTitle(t.when),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  whenChip(t.anyTime, _When.any),
                  whenChip(t.thisWeek, _When.week),
                  whenChip(t.weekend, _When.weekend),
                  whenChip(
                    _when == _When.day && _day != null ? fullDate(context, _day!) : t.pickDate,
                    _When.day,
                    icon: Icons.calendar_today_outlined,
                    onTap: () async {
                      await _chooseDay();
                      setSheet(() {});
                    },
                  ),
                ]),
                const SizedBox(height: 18),
                DropdownButtonFormField<String?>(
                  initialValue: _area,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.place_outlined), labelText: t.area),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(t.allAreas)),
                    for (final a in areaKeys) DropdownMenuItem<String?>(value: a, child: Text(areaName(context, a))),
                  ],
                  onChanged: (v) => change(() => _area = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.near_me_outlined),
                  title: Text(t.nearMe, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(t.nearMeHint),
                  value: _nearMe,
                  onChanged: (_) async {
                    await _toggleNearMe();
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _saveAlert();
                  },
                  icon: const Icon(Icons.notification_add_outlined),
                  label: Text(t.alertMeForThis),
                ),
                const SizedBox(height: 10),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t.showResults)),
              ]),
            ),
          );
        },
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
    Widget square({required IconData icon, required String tooltip, required VoidCallback onTap, int badge = 0}) =>
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: IconButton.outlined(
            tooltip: tooltip,
            style: IconButton.styleFrom(
              minimumSize: const Size(50, 50),
              backgroundColor: badge > 0 ? AppColors.nileTint : Colors.white,
              side: const BorderSide(color: AppColors.field, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onTap,
            icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon)),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t.searchShort,
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
        ),
        square(icon: Icons.tune_rounded, tooltip: t.filters, onTap: _openFilters, badge: _extraFilters),
        square(
          icon: _showMap ? Icons.view_list_outlined : Icons.map_outlined,
          tooltip: _showMap ? t.showList : t.showMap,
          onTap: () => setState(() => _showMap = !_showMap),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(labels[f]!),
                selected: _filter == f,
                showCheckmark: false,
                onSelected: (_) {
                  _filter = f;
                  _load();
                },
              ),
            ),
        ]),
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
