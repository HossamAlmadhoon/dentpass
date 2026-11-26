import 'package:flutter/material.dart';

import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/widgets.dart';

/// Rate the other person after a slot: 1 to 5 stars and an optional comment.
/// Returns true when the rating was sent.
Future<bool> showReviewSheet(BuildContext context, {required String bookingId, required String title}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReviewSheet(bookingId: bookingId, title: title),
  );
  if (sent == true && context.mounted) showMessage(context, AppLocalizations.of(context).ratingSent);
  return sent == true;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.bookingId, required this.title});
  final String bookingId;
  final String title;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.submitReview(widget.bookingId, _stars, _comment.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(t.howWasIt, style: const TextStyle(fontSize: 15, color: AppColors.body)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 40,
                    tooltip: '$i',
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i <= _stars ? const Color(0xFFB7791F) : AppColors.field,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: t.commentOptional),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
            FilledButton(
              onPressed: _busy || _stars == 0 ? null : _send,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(t.sendRating),
            ),
          ],
        ),
      ),
    );
  }
}
