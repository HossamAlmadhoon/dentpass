import 'package:flutter/material.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// A member's public page: who they are, their rating, upcoming slots and reviews.
class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key, required this.userId, required this.viewer});
  final String userId;
  final Profile viewer;

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  late Future<(Member?, List<Review>, List<Slot>)> _data = _fetch();

  Future<(Member?, List<Review>, List<Slot>)> _fetch() async {
    final results = await Future.wait([
      repo.member(widget.userId),
      repo.reviewsOf(widget.userId),
      repo.feed(hostId: widget.userId),
    ]);
    return (results[0] as Member?, results[1] as List<Review>, results[2] as List<Slot>);
  }

  void _reload() => setState(() => _data = _fetch());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<(Member?, List<Review>, List<Slot>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          final (member, reviews, slots) = snap.data!;
          if (member == null) return EmptyView(text: t.noMembers);
          final lang = Localizations.localeOf(context).languageCode;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Row(children: [
                  Avatar(
                    name: member.fullName,
                    photoUrl: member.avatarPath == null ? null : repo.avatarUrl(member.avatarPath!),
                    radius: 36,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(member.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(
                        [roleName(t, member.role), areaName(context, member.area)]
                            .where((s) => s.isNotEmpty)
                            .join(lang == 'ar' ? '، ' : ', '),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.verified, size: 16, color: AppColors.nile),
                        const SizedBox(width: 4),
                        Text(t.syndicateChecked, style: const TextStyle(fontSize: 13, color: AppColors.nile, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    RatingLine(rating: member.rating, count: member.reviews),
                    const SizedBox(height: 8),
                    Text(t.memberSince(monthShort(context, member.memberSince) + ' ${member.memberSince.year}'),
                        style: const TextStyle(color: AppColors.body)),
                    Text(t.hostedCount(member.hosted), style: const TextStyle(color: AppColors.body)),
                    Text(t.attendedCount(member.attended), style: const TextStyle(color: AppColors.body)),
                  ]),
                ),
                if (member.bio.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(member.bio, style: const TextStyle(fontSize: 15, height: 1.6, color: AppColors.body)),
                ],
                const SizedBox(height: 24),
                Text(t.openSlots, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (slots.isEmpty) Text(t.noOpenSlots, style: const TextStyle(color: AppColors.muted)),
                for (final s in slots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SlotCard(
                      slot: s,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SlotDetailScreen(slotId: s.id, profile: widget.viewer)),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Text(t.reviewsTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (reviews.isEmpty) Text(t.noReviews, style: const TextStyle(color: AppColors.muted)),
                for (final r in reviews) _ReviewTile(review: r),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    final r = review;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= r.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18, color: i <= r.stars ? const Color(0xFFB7791F) : AppColors.field),
          const SizedBox(width: 8),
          Expanded(
            child: Text(r.reviewerName,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(fullDate(context, r.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        if (r.slotTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(r.slotTitle, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
        if (r.comment.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(r.comment, style: const TextStyle(fontSize: 15, height: 1.5)),
          ),
      ]),
    );
  }
}
