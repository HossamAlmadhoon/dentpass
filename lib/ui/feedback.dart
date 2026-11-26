import 'package:flutter/material.dart';

import 'package:dentpass/theme.dart';

/// Grey outlines of tickets while the real ones load, gently pulsing.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 4});
  final int count;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.track, borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final list = Column(children: [
      for (var i = 0; i < widget.count; i++)
        Container(
          height: 112,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 68,
              decoration: const BoxDecoration(
                color: AppColors.track,
                borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  _bar(70, 10),
                  const SizedBox(height: 10),
                  _bar(double.infinity, 14),
                  const SizedBox(height: 8),
                  _bar(140, 10),
                  const SizedBox(height: 12),
                  _bar(90, 10),
                ]),
              ),
            ),
          ]),
        ),
    ]);
    if (reduceMotion) return list;
    return FadeTransition(opacity: Tween(begin: 0.55, end: 1.0).animate(_pulse), child: list);
  }
}

/// A full screen that confirms something worked and says what happens next.
class DoneScreen extends StatelessWidget {
  const DoneScreen({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.color = AppColors.nile,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 24),
              Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.body)),
              const Spacer(flex: 2),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
