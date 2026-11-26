import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentpass/content/legal.dart';
import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/kinds.dart';
import 'package:dentpass/ui/widgets.dart';

// ------------------------------------------------------------------ terms and privacy
enum LegalPage { terms, privacy }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.page});
  final LegalPage page;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final sections = switch (page) {
      LegalPage.terms => ar ? termsAr : termsEn,
      LegalPage.privacy => ar ? privacyAr : privacyEn,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(page == LegalPage.terms ? t.termsTitle : t.privacyTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(legalUpdated, style: const TextStyle(color: AppColors.muted)),
          for (final s in sections) ...[
            const SizedBox(height: 20),
            Text(s.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(s.body, style: const TextStyle(fontSize: 15, height: 1.65, color: AppColors.body)),
          ],
        ],
      ),
    );
  }
}

/// "I agree to the Terms of use and the Privacy policy", with both readable.
class TermsAgreement extends StatelessWidget {
  const TermsAgreement({super.key, required this.value, required this.onChanged, this.showError = false});
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    void open(LegalPage p) => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen(page: p)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(t.agreeTerms, style: const TextStyle(fontSize: 14.5)),
      ),
      Wrap(spacing: 4, children: [
        TextButton(onPressed: () => open(LegalPage.terms), child: Text(t.termsTitle)),
        TextButton(onPressed: () => open(LegalPage.privacy), child: Text(t.privacyTitle)),
      ]),
      if (showError && !value)
        Text(t.mustAgree, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ------------------------------------------------------------------ help
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final faqs = [
      (t.faq1q, t.faq1a),
      (t.faq2q, t.faq2a),
      (t.faq3q, t.faq3a),
      (t.faq4q, t.faq4a),
      (t.faq5q, t.faq5a),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t.help, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          FutureBuilder<AppSettings>(
            future: repo.settings(),
            builder: (context, snap) {
              final number = snap.data?.supportWhatsapp;
              if (number == null || number.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton.icon(
                  onPressed: () => openWhatsApp(number),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(t.contactWhatsapp),
                ),
              );
            },
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (q, a) in faqs)
                ExpansionTile(
                  shape: const Border(),
                  title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(a, style: const TextStyle(height: 1.55, color: AppColors.body))],
                ),
            ]),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(t.termsTitle),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalScreen(page: LegalPage.terms))),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(t.privacyTitle),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalScreen(page: LegalPage.privacy))),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ welcome tour
const _tourKey = 'welcome_tour_seen_v1';

Future<bool> tourSeen() async => (await SharedPreferences.getInstance()).getBool(_tourKey) ?? false;

class WelcomeTour extends StatefulWidget {
  const WelcomeTour({super.key});

  @override
  State<WelcomeTour> createState() => _WelcomeTourState();
}

class _WelcomeTourState extends State<WelcomeTour> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tourKey, true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final steps = [
      (SlotKind.observe, t.tour1Title, t.tour1Body),
      (SlotKind.rent, t.tour2Title, t.tour2Body),
      (SlotKind.cover, t.tour3Title, t.tour3Body),
    ];
    final last = _page == steps.length - 1;
    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: _finish, child: Text(t.skip))]),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (kind, title, body) in steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(color: kindStyle(kind).tint, borderRadius: BorderRadius.circular(32)),
                          child: Icon(kindStyle(kind).icon, size: 56, color: kindStyle(kind).ink),
                        ),
                        const SizedBox(height: 28),
                        Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
                        const SizedBox(height: 12),
                        Text(body, style: const TextStyle(fontSize: 17, height: 1.55, color: AppColors.body)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < steps.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _page ? 22 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.nile : AppColors.field,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: FilledButton(
              onPressed: last
                  ? _finish
                  : () => _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
              child: Text(last ? t.getStarted : t.tourNext),
            ),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ report
Future<void> showReportSheet(BuildContext context, {String? memberId, String? slotId, required String title}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(memberId: memberId, slotId: slotId, title: title),
  );
  if (sent == true && context.mounted) showMessage(context, AppLocalizations.of(context).reportSent);
}

String reasonLabel(AppLocalizations t, ReportReason r) => switch (r) {
      ReportReason.noShow => t.reasonNoShow,
      ReportReason.unsafe => t.reasonUnsafe,
      ReportReason.fake => t.reasonFake,
      ReportReason.payment => t.reasonPayment,
      ReportReason.behaviour => t.reasonBehaviour,
      ReportReason.other => t.reasonOther,
    };

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.memberId, required this.slotId, required this.title});
  final String? memberId;
  final String? slotId;
  final String title;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.report(memberId: widget.memberId, slotId: widget.slotId, reason: _reason!, details: _details.text.trim());
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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(t.reportWhy, style: const TextStyle(color: AppColors.body)),
          const SizedBox(height: 8),
          RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final r in ReportReason.values)
                RadioListTile<ReportReason>(
                  contentPadding: EdgeInsets.zero,
                  value: r,
                  title: Text(reasonLabel(t, r)),
                ),
            ]),
          ),
          TextField(
            controller: _details,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: t.reportDetails),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: _busy || _reason == null ? null : _send,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(t.sendReport),
          ),
        ]),
      ),
    );
  }
}
