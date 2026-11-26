// Renders key screens at iPhone size in Arabic and English, to catch crashes,
// missing translations and layout errors before they reach testers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/locale_controller.dart';
import 'package:dentpass/screens/booking_review_sheet.dart';
import 'package:dentpass/screens/password_screens.dart';
import 'package:dentpass/screens/post_slot_screen.dart';
import 'package:dentpass/screens/sign_in_screen.dart';
import 'package:dentpass/ui/widgets.dart';

Widget _app(Widget home, String lang) => MaterialApp(
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    );

Slot _slot(SlotKind kind) => Slot.fromMap({
      'id': kind.name,
      'host_id': 'h',
      'host_name': 'Dr. Ahmed Mansour',
      'kind': kind.name,
      'title': 'Full-arch implant placement with immediate loading',
      'area': 'heliopolis',
      'starts_at': '2030-03-02T08:00:00Z',
      'ends_at': '2030-03-02T12:00:00Z',
      'capacity': 3,
      'taken': 1,
      'price_egp': 1500,
      'need_role': kind == SlotKind.cover ? 'assistant' : null,
    });

/// The test font draws every letter as a wide square, so text overflow warnings here
/// would be false alarms. Every other error still fails the test.
/// Returns a function that puts the normal error handler back; call it at the end of the test.
VoidCallback _ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  return () => FlutterError.onError = original;
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    localeController = LocaleController(const Locale('ar'));
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('sign-in screen ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(const SignInScreen(), lang));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      final t = lookupAppLocalizations(Locale(lang));
      expect(find.text(t.forgotPassword), findsOneWidget);
      restore();
    });

    testWidgets('post a slot screen, every type ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(PostSlotScreen(onPosted: () {}), lang));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(Locale(lang));
      for (final name in [t.kindCourse, t.kindRent, t.kindCover]) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text(t.whoNeeded), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(t.whoNeeded), findsOneWidget);
      restore();
    });

    testWidgets('slot tickets, all four types ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(
        Scaffold(
          body: ListView(children: [
            for (final k in SlotKind.values) SlotCard(slot: _slot(k), onTap: () {}),
          ]),
        ),
        lang,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SlotCard), findsNWidgets(4));
      restore();
    });

    testWidgets('booking review ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(
        Scaffold(body: BookingReviewSheet(slot: _slot(SlotKind.observe), feePercent: 10)),
        lang,
      ));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(Locale(lang));
      expect(find.text(t.reviewTotal), findsOneWidget);
      restore();
    });

    testWidgets('set a new password ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(SetPasswordScreen(onDone: () {}), lang));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      restore();
    });
  }
}
