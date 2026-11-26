import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
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
        _ => n.type,
      };

  void _open(AppNotification n) {
    final slotId = n.slotId;
    if (slotId == null) return;
    final hostSide = n.type == 'booking_requested' || n.type == 'booking_cancelled';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => hostSide
            ? ManageSlotScreen(slotId: slotId)
            : SlotDetailScreen(slotId: slotId, profile: widget.profile),
      ),
    );
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
                leading: Icon(
                  n.read ? Icons.notifications_none : Icons.notifications_active,
                  color: n.read ? AppColors.muted : AppColors.nile,
                ),
                title: Text(_text(t, n),
                    style: TextStyle(fontSize: 15, fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                subtitle: Text('${fullDate(context, n.createdAt)} ${time(context, n.createdAt)}'),
                onTap: n.slotId == null ? null : () => _open(n),
              );
            },
          );
        },
      ),
    );
  }
}
