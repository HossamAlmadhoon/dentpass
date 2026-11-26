import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dentpass/data/areas.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';

/// Turns a server error into a sentence the user can act on.
String errorText(BuildContext context, Object e) {
  final t = AppLocalizations.of(context);
  final String raw = switch (e) {
    PostgrestException(:final message) => message,
    AuthException(:final message) => message,
    _ => '',
  };
  final msg = raw.toLowerCase();
  if (msg.contains('slot full')) return t.errSlotFull;
  if (msg.contains('already booked')) return t.errAlreadyBooked;
  if (msg.contains('slot closed')) return t.errSlotClosed;
  if (msg.contains('role mismatch')) return t.errRoleMismatch;
  if (msg.contains('invalid login')) return t.wrongLogin;
  return t.errGeneric;
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> callNumber(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// Egyptian mobile numbers (01xxxxxxxxx) become wa.me/201xxxxxxxxx.
Future<void> openWhatsApp(String phone) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0')) digits = '20${digits.substring(1)}';
  return launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication);
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorText(context, error), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(t.retry)),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.actionLabel, this.onAction});
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.body)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (bg, fg) = switch (status) {
      BookingStatus.pending => (AppColors.amberTint, AppColors.amber),
      BookingStatus.accepted => (AppColors.nileTint, AppColors.nile),
      BookingStatus.declined => (AppColors.dangerTint, AppColors.danger),
      BookingStatus.cancelled => (AppColors.track, AppColors.body),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(statusName(t, status), style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

/// A row of "label  value" used on detail screens.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4))),
        ],
      ),
    );
  }
}

String availabilityText(AppLocalizations t, Slot s) {
  if (s.kind == SlotKind.cover) return t.openForOffers;
  if (s.isFull) return t.full;
  return t.placesLeft(s.placesLeft);
}

String priceText(BuildContext context, int amount) {
  final t = AppLocalizations.of(context);
  return amount == 0 ? t.free : t.priceEgp(money(context, amount));
}

/// A slot shown as a ticket: the date on a coloured stub, the details beside it.
class SlotCard extends StatelessWidget {
  const SlotCard({super.key, required this.slot, required this.onTap, this.trailing});
  final Slot slot;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ks = kindStyle(slot.kind);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 68,
                color: ks.tint,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(dayOfWeek(context, slot.startsAt),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ks.ink)),
                    Text(dayOfMonth(context, slot.startsAt),
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1, color: ks.ink)),
                    Text(monthShort(context, slot.startsAt),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ks.ink)),
                  ],
                ),
              ),
              const _Perforation(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(ks.icon, size: 16, color: ks.ink),
                        const SizedBox(width: 6),
                        Text(kindName(t, slot.kind),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ks.ink)),
                      ]),
                      const SizedBox(height: 4),
                      Text(slot.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
                      const SizedBox(height: 2),
                      Text(
                        [slot.hostName, areaName(context, slot.area)]
                            .where((s) => s.isNotEmpty)
                            .join(Localizations.localeOf(context).languageCode == 'ar' ? '، ' : ', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: trailing ??
                                Text(availabilityText(t, slot),
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.body)),
                          ),
                          Text(priceText(context, slot.priceEgp),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 2, child: CustomPaint(painter: _DashPainter()));
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 2;
    for (double y = 4; y < size.height - 4; y += 9) {
      canvas.drawLine(Offset(1, y), Offset(1, y + 5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pick a photo from the gallery or camera. Shows whether one is already added.
class PhotoPickTile extends StatelessWidget {
  const PhotoPickTile({super.key, required this.label, required this.hasPhoto, required this.onPicked});
  final String label;
  final bool hasPhoto;
  final ValueChanged<XFile> onPicked;

  Future<void> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(AppLocalizations.of(ctx).camera),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(AppLocalizations.of(ctx).gallery),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (file != null) onPicked(file);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      color: hasPhoto ? AppColors.nileTint : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: hasPhoto ? AppColors.nile : AppColors.field, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(hasPhoto ? Icons.check_circle : Icons.add_a_photo_outlined,
                color: hasPhoto ? AppColors.nile : AppColors.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            Text(hasPhoto ? t.photoAdded : t.addPhoto,
                style: TextStyle(fontSize: 13, color: hasPhoto ? AppColors.nile : AppColors.muted)),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}
