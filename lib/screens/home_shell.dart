import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/bookings_screen.dart';
import 'package:dentpass/screens/explore_screen.dart';
import 'package:dentpass/screens/info_screens.dart';
import 'package:dentpass/screens/post_slot_screen.dart';
import 'package:dentpass/screens/profile_screen.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/services/notifications.dart';
import 'package:dentpass/ui/feedback.dart';

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
  int _postKey = 0;

  @override
  void initState() {
    super.initState();
    PhoneNotifications.instance.prepare();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await tourSeen() && mounted) {
        await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WelcomeTour()));
      }
    });
  }

  void _go(int i) => setState(() => _tab = i);

  Future<void> _posted(String slotId) async {
    final t = AppLocalizations.of(context);
    setState(() {
      _tab = 0;
      _postKey++; // a fresh, empty form next time
    });
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => DoneScreen(
          title: t.postedTitle,
          body: t.postedBody,
          primaryLabel: t.viewSlot,
          onPrimary: () => Navigator.pushReplacement(
            ctx,
            MaterialPageRoute(builder: (_) => SlotDetailScreen(slotId: slotId, profile: widget.profile)),
          ),
          secondaryLabel: t.backToExplore,
          onSecondary: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final body = switch (_tab) {
      0 => ExploreScreen(profile: widget.profile, onPostSlot: () => _go(1)),
      1 => PostSlotScreen(key: ValueKey(_postKey), onPosted: _posted),
      2 => BookingsScreen(profile: widget.profile),
      _ => ProfileScreen(profile: widget.profile, onChanged: widget.onProfileChanged),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t.tabExplore),
          NavigationDestination(icon: const Icon(Icons.add_box_outlined), selectedIcon: const Icon(Icons.add_box), label: t.tabPost),
          NavigationDestination(icon: const Icon(Icons.event_note_outlined), selectedIcon: const Icon(Icons.event_note), label: t.tabBookings),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t.tabProfile),
        ],
      ),
    );
  }
}
