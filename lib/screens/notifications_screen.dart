import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/admin_screen.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/screens/member_screen.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.profile});
  final Profile profile;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _items = _fetch();

  Future<List<AppNotification>> _fetch() async {
    final items = await repo.notifications();
    if (items.any((n) => !n.read)) await repo.markAllRead();
    return items;
  }

  String _text(AppLocalizations t, AppNotification n) => switch (n.type) {
        'booking_requested' => t.nRequested(n.slotTitle),
        'booking_accepted' => t.nAccepted(n.slotTitle),
        'booking_declined' => t.nDeclined(n.slotTitle),
        'booking_cancelled' => t.nCancelled(n.slotTitle),
        'verification_approved' => t.nApproved,
        'verification_rejected' => t.nRejected,
        'slot_updated' => t.nUpdated(n.slotTitle),
        'slot_cancelled' => t.nSlotCancelled(n.slotTitle),
        'review_received' => t.nReview(n.slotTitle),
        'account_suspended' => t.nSuspended,
        'account_reinstated' => t.nReinstated,
        'reminder' => t.nReminder(n.slotTitle),
        'host_reminder' => t.nHostReminder(n.slotTitle),
        'new_slot' => t.nNewSlot(n.slotTitle),
        'report_received' => t.nReport,
        'booking_paid' => t.nPaid(n.slotTitle),
        _ => n.type,
      };

  /// Each kind of news has its own picture and colour, so the list can be read at a glance.
  (IconData, Color, Color) _look(String type) => switch (type) {
        'booking_accepted' || 'verification_approved' || 'account_reinstated' =>
          (Icons.check_circle_outline, AppColors.nile, AppColors.nileTint),
        'booking_paid' => (Icons.payments_outlined, AppColors.nile, AppColors.nileTint),
        'booking_requested' => (Icons.inbox_outlined, AppColors.amber, AppColors.amberTint),
        'booking_declined' || 'booking_cancelled' || 'slot_cancelled' || 'verification_rejected' || 'account_suspended' =>
          (Icons.cancel_outlined, AppColors.danger, AppColors.dangerTint),
        'reminder' || 'host_reminder' => (Icons.alarm_rounded, AppColors.blue, AppColors.blueTint),
        'slot_updated' => (Icons.edit_calendar_outlined, AppColors.blue, AppColors.blueTint),
        'review_received' => (Icons.star_rounded, Stars.gold, AppColors.amberTint),
        'new_slot' => (Icons.campaign_outlined, AppColors.nile, AppColors.nileTint),
        'report_received' => (Icons.flag_outlined, AppColors.danger, AppColors.dangerTint),
        _ => (Icons.notifications_none, AppColors.muted, AppColors.track),
      };

  bool _canOpen(AppNotification n) =>
      n.type == 'review_received' || (n.type == 'report_received' && widget.profile.isAdmin) || n.slotId != null;

  void _open(AppNotification n) {
    final slotId = n.slotId;
    final Widget screen;
    if (n.type == 'review_received') {
      screen = MemberScreen(userId: widget.profile.id, viewer: widget.profile);
    } else if (n.type == 'report_received') {
      screen = const AdminScreen(initialTab: 4);
    } else if (slotId == null) {
      return;
    } else if (n.type == 'booking_requested' || n.type == 'booking_cancelled' || n.type == 'host_reminder' || n.type == 'booking_paid') {
      screen = ManageSlotScreen(slotId: slotId, profile: widget.profile);
    } else {
      screen = SlotDetailScreen(slotId: slotId, profile: widget.profile);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.notifications, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<List<AppNotification>>(
        future: _items,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() => _items = _fetch()));
          }
          if (!snap.hasData) return const LoadingView();
          final items = snap.data!;
          if (items.isEmpty) return EmptyView(text: t.noNotifications);
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, i) => const Divider(),
            itemBuilder: (context, i) {
              final n = items[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: Builder(builder: (_) {
                  final (icon, fg, bg) = _look(n.type);
                  return Badge(
                    isLabelVisible: !n.read,
                    smallSize: 10,
                    backgroundColor: AppColors.danger,
                    child: CircleAvatar(radius: 21, backgroundColor: bg, child: Icon(icon, color: fg, size: 22)),
                  );
                }),
                title: Text(_text(t, n),
                    style: TextStyle(fontSize: 15, fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                subtitle: Text('${dayText(context, n.createdAt)} ${time(context, n.createdAt)}'),
                onTap: _canOpen(n) ? () => _open(n) : null,
              );
            },
          );
        },
      ),
    );
  }
}
