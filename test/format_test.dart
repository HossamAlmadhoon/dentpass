import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/ui/format.dart';

void main() {
  test('Arabic-Indic digits become 0–9', () {
    expect(latinDigits('السبت ٢٨ نوفمبر ١٠:٣٠'), 'السبت 28 نوفمبر 10:30');
    expect(latinDigits('١٬٥٠٠'), '1,500');
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('12-hour times and today/tomorrow ($lang)', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(lang),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      final t = lookupAppLocalizations(Locale(lang));
      final now = DateTime.now();
      expect(time(ctx, DateTime(2026, 1, 1, 14, 30)), lang == 'ar' ? '2:30 م' : '2:30 PM');
      expect(time(ctx, DateTime(2026, 1, 1, 0, 0)), lang == 'ar' ? '12 ص' : '12 AM');
      expect(dayText(ctx, now), t.today);
      expect(dayText(ctx, DateTime(now.year, now.month, now.day + 1, 9)), t.tomorrow);
      expect(RegExp('[٠-٩]').hasMatch(whenText(ctx, now.add(const Duration(days: 5)), now.add(const Duration(days: 5, hours: 2)))), isFalse);
    });
  }
}
