import 'package:flutter/material.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

/// The step before sending a request: what it costs, how payment works, an optional message.
class BookingReviewSheet extends StatefulWidget {
  const BookingReviewSheet({super.key, required this.slot, required this.feePercent});
  final Slot slot;
  final int feePercent;

  @override
  State<BookingReviewSheet> createState() => _BookingReviewSheetState();
}

class _BookingReviewSheetState extends State<BookingReviewSheet> {
  final _message = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.book(widget.slot.id, _message.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = widget.slot;
    final isCover = s.kind == SlotKind.cover;
    final fee = isCover ? 0 : (s.priceEgp * widget.feePercent / 100).round();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.reviewTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(s.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(whenText(context, s.startsAt, s.endsAt), style: const TextStyle(color: AppColors.muted)),
            const Divider(height: 28),
            if (isCover)
              Text(t.reviewCoverNote(priceText(context, s.priceEgp)),
                  style: const TextStyle(fontSize: 15, height: 1.5))
            else ...[
              _row(t.reviewPrice, priceText(context, s.priceEgp)),
              _row(t.reviewFee, priceText(context, fee)),
              const Divider(height: 20),
              _row(t.reviewTotal, priceText(context, s.priceEgp + fee), bold: true),
              const SizedBox(height: 8),
              Text(t.reviewPayNote, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.body)),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: t.messageToHost),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(isCover ? actionLabel(t, s.kind) : t.confirmRequest),
            ),
          ],
        ),
      ),
    );
  }
}
