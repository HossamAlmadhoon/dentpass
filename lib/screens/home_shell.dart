import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/bookings_screen.dart';
import 'package:dentpass/screens/explore_screen.dart';
import 'package:dentpass/screens/post_slot_screen.dart';
import 'package:dentpass/screens/profile_screen.dart';
import 'package:dentpass/ui/widgets.dart';

/// The four tabs an approved member sees.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.profile, required this.onProfileChanged});
  final Profile profile;
  final VoidCallback onProfileChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final body = switch (_tab) {
      0 => ExploreScreen(profile: widget.profile, onPostSlot: () => _go(1)),
      1 => PostSlotScreen(onPosted: () {
          showMessage(context, t.posted);
          _go(0);
        }),
      2 => BookingsScreen(profile: widget.profile),
      _ => ProfileScreen(profile: widget.profile, onChanged: widget.onProfileChanged),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.search), label: t.tabExplore),
          NavigationDestination(icon: const Icon(Icons.add_box_outlined), selectedIcon: const Icon(Icons.add_box), label: t.tabPost),
          NavigationDestination(icon: const Icon(Icons.event_note_outlined), selectedIcon: const Icon(Icons.event_note), label: t.tabBookings),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t.tabProfile),
        ],
      ),
    );
  }
}
