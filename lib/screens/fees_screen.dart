import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/theme.dart';
import 'package:dentpass/ui/format.dart';
import 'package:dentpass/ui/widgets.dart';

String monthName(BuildContext context, DateTime m) =>
    latinDigits(DateFormat.yMMMM(Localizations.localeOf(context).languageCode).format(m));

/// A host's DentPass fees, month by month, and where to pay them.
class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key});

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> {
  late Future<(List<FeeMonth>, AppSettings)> _data = _fetch();
  String? _busyMonth;

  Future<(List<FeeMonth>, AppSettings)> _fetch() async {
    final results = await Future.wait([repo.hostStatement(), repo.settings()]);
    return (results[0] as List<FeeMonth>, results[1] as AppSettings);
  }

  void _reload() => setState(() => _data = _fetch());

  Future<void> _markPaid(FeeMonth m) async {
    final t = AppLocalizations.of(context);
    if (!await confirmAction(context, title: t.markPaidQuestion, action: t.markPaid)) return;
    setState(() => _busyMonth = m.month.toIso8601String());
    try {
      await repo.markFeesPaid(m.month);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busyMonth = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.dentpassFees, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<(List<FeeMonth>, AppSettings)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          final (months, settings) = snap.data!;
          final instapay = settings.dentpassInstapay ?? '';
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.nileTint, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    settings.feePercent == 0 ? t.feesFreePilot : t.feesHowItWorks('${settings.feePercent}'),
                    style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink),
                  ),
                ),
                const SizedBox(height: 16),
                if (months.isEmpty) EmptyView(text: t.feesNothingYet),
                for (final m in months)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(monthName(context, m.month),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                        _FeeStatus(month: m),
                      ]),
                      const SizedBox(height: 6),
                      Text(t.feesMonthLine(m.bookings, priceText(context, m.earnedEgp)),
                          style: const TextStyle(color: AppColors.body)),
                      const SizedBox(height: 2),
                      Text(t.feesOwed(priceText(context, m.feeEgp)),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (m.owes && m.hostPaidAt == null) ...[
                        const SizedBox(height: 12),
                        if (instapay.isNotEmpty)
                          Material(
                            color: AppColors.ground,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: instapay));
                                if (context.mounted) showMessage(context, t.copied);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(instapay,
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.start,
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                  const Icon(Icons.copy_rounded, size: 20, color: AppColors.nile),
                                  const SizedBox(width: 4),
                                  Text(t.copy, style: const TextStyle(color: AppColors.nile, fontWeight: FontWeight.w700)),
                                ]),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _busyMonth == m.month.toIso8601String() ? null : () => _markPaid(m),
                          icon: const Icon(Icons.done_rounded),
                          label: Text(t.markPaid),
                        ),
                      ],
                    ]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FeeStatus extends StatelessWidget {
  const _FeeStatus({required this.month});
  final FeeMonth month;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (text, fg, bg) = month.feeEgp == 0
        ? (t.feesNone, AppColors.body, AppColors.track)
        : month.confirmedAt != null
            ? (t.feesSettled, AppColors.nile, AppColors.nileTint)
            : month.hostPaidAt != null
                ? (t.feesChecking, AppColors.blue, AppColors.blueTint)
                : (t.feesDue, AppColors.amber, AppColors.amberTint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}
