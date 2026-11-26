import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// The alerts a member saved from Explore, with a way to remove each.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<List<SlotAlert>> _items = repo.alerts();

  void _reload() => setState(() => _items = repo.alerts());

  String _describe(BuildContext context, SlotAlert a) {
    final t = AppLocalizations.of(context);
    final kinds = a.kinds == null ? t.alertAll : a.kinds!.map((k) => kindName(t, k)).join(' / ');
    final area = a.area == null ? t.allAreas : areaName(context, a.area);
    return '$kinds\n$area';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.myAlerts, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<List<SlotAlert>>(
        future: _items,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          final items = snap.data!;
          if (items.isEmpty) return EmptyView(text: t.noAlerts);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final a = items[i];
              return Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.notifications_active_outlined, color: AppColors.nile),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_describe(context, a), style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600))),
                  IconButton(
                    tooltip: t.delete,
                    onPressed: () async {
                      try {
                        await repo.removeAlert(a.id);
                        _reload();
                      } catch (e) {
                        if (context.mounted) showMessage(context, errorText(context, e));
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
