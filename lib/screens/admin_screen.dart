import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// Admins check new members' syndicate cards and IDs, then approve or reject.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<List<Profile>> _items = repo.pendingMembers();

  void _reload() => setState(() => _items = repo.pendingMembers());

  Future<void> _decide(Profile p, bool approve) async {
    final t = AppLocalizations.of(context);
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.rejectReason),
          content: TextField(controller: controller, autofocus: true, maxLength: 300, maxLines: 3),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(t.send)),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    }
    try {
      await repo.setVerification(p.id, approve, reason: reason);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.adminTitle, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<List<Profile>>(
        future: _items,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          final items = snap.data!;
          if (items.isEmpty) return EmptyView(text: t.noPending);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final p in items)
                Card(
                  color: Colors.white,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('${roleName(t, p.role)} · ${areaName(context, p.area)}',
                          style: const TextStyle(color: AppColors.muted)),
                      if (p.syndicateNo != null) Text('${t.syndicateNo}: ${p.syndicateNo}'),
                      if (p.phone != null) Text('${t.phone}: ${p.phone}', textDirection: TextDirection.ltr),
                      const SizedBox(height: 12),
                      Row(children: [
                        if (p.cardPath != null) Expanded(child: _DocImage(label: t.syndicateCard, path: p.cardPath!)),
                        if (p.cardPath != null) const SizedBox(width: 10),
                        if (p.idPath != null) Expanded(child: _DocImage(label: t.nationalId, path: p.idPath!)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: FilledButton(onPressed: () => _decide(p, true), child: Text(t.approve))),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton(onPressed: () => _decide(p, false), child: Text(t.reject))),
                      ]),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DocImage extends StatelessWidget {
  const _DocImage({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: FutureBuilder<String>(
            future: repo.verificationFileUrl(path),
            builder: (context, snap) {
              if (!snap.hasData) return Container(color: AppColors.track);
              return InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(snap.data!))),
                ),
                child: Image.network(snap.data!, fit: BoxFit.cover),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
