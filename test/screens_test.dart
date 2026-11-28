// Renders key screens at iPhone size in Arabic and English, to catch crashes,
// missing translations and layout errors before they reach testers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/locale_controller.dart';
import 'package:dentpass/screens/basic_details_screen.dart';
import 'package:dentpass/screens/booking_review_sheet.dart';
import 'package:dentpass/screens/edit_profile_screen.dart';
import 'package:dentpass/screens/info_screens.dart';
import 'package:dentpass/screens/password_screens.dart';
import 'package:dentpass/screens/post_slot_screen.dart';
import 'package:dentpass/screens/review_sheet.dart';
import 'package:dentpass/screens/sign_in_screen.dart';
import 'package:dentpass/screens/verify_gate.dart';
import 'package:dentpass/screens/verify_screen.dart';
import 'package:dentpass/ui/feedback.dart';
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

Profile _profile(String status, {String name = 'Dr. Sara Adel', String? phone = '01012345678'}) => Profile.fromMap({
      'id': 'me',
      'full_name': name,
      'phone': phone,
      'role': 'dentist',
      'area': 'maadi',
      'status': status,
      'rejection_reason': status == 'rejected' ? 'The card photo is blurry' : null,
    });

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
      await tester.pumpWidget(_app(PostSlotScreen(onPosted: (_) {}), lang));
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
      // Guests pay the listed price: no DentPass fee or total lines
      expect(find.text(t.reviewPrice), findsOneWidget);
      expect(find.text(t.reviewFee), findsNothing);
      expect(find.text(t.reviewPayNote), findsOneWidget);
      restore();
    });

    testWidgets('edit a posted slot ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final existing = Slot.fromMap({
        'id': 'e1', 'host_id': 'h', 'kind': 'cover', 'title': 'Evening shift', 'description': 'Fillings and scaling',
        'area': 'maadi', 'address': '9 Road 233', 'starts_at': '2030-03-02T14:00:00Z', 'ends_at': '2030-03-02T20:00:00Z',
        'capacity': 1, 'price_egp': 900, 'need_role': 'dentist', 'lat': 29.96, 'lng': 31.25, 'exact_location': true,
      });
      await tester.pumpWidget(_app(PostSlotScreen(existing: existing, onPosted: (_) {}), lang));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(Locale(lang));
      expect(find.text(t.editSlot), findsOneWidget);
      expect(find.text('Evening shift'), findsOneWidget);
      expect(find.text(t.whatPosting), findsNothing, reason: 'the type is fixed when editing');
      expect(find.text(t.changeLocation), findsOneWidget);
      restore();
    });

    testWidgets('edit profile ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final me = Profile.fromMap({
        'id': 'me', 'full_name': 'Dr. Mariam Adel', 'phone': '01012345678', 'role': 'dentist', 'area': 'nasr_city',
        'status': 'approved', 'bio': 'General dentist',
      });
      await tester.pumpWidget(_app(EditProfileScreen(profile: me), lang));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(Locale(lang));
      expect(find.text(t.lockedDetails), findsOneWidget);
      expect(find.text('General dentist'), findsOneWidget);
      restore();
    });

    testWidgets('rating sheet needs at least one star ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReviewSheet(context, bookingId: 'b1', title: 'Rate the host'),
              child: const Text('open'),
            ),
          ),
        ),
        lang,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(Locale(lang));
      final send = find.widgetWithText(FilledButton, t.sendRating);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
      restore();
    });

    testWidgets('sign-up needs the terms agreed ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      await tester.pumpWidget(_app(const SignInScreen(), lang));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.tap(find.text(t.noAccount));
      await tester.pumpAndSettle();
      expect(find.text(t.agreeTerms), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, t.signUp));
      await tester.pumpAndSettle();
      expect(find.text(t.mustAgree), findsOneWidget, reason: 'nothing is sent until the terms are agreed');
      restore();
    });

    testWidgets('terms and privacy pages ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      for (final page in LegalPage.values) {
        await tester.pumpWidget(_app(LegalScreen(page: page), lang));
        await tester.pumpAndSettle();
        expect(find.text(page == LegalPage.terms ? t.termsTitle : t.privacyTitle), findsOneWidget);
      }
      restore();
    });

    testWidgets('welcome tour goes through three pages ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelcomeTour())),
              child: const Text('open'),
            ),
          ),
        ),
        lang,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(t.tour1Title), findsOneWidget);
      await tester.tap(find.text(t.tourNext));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.tourNext));
      await tester.pumpAndSettle();
      expect(find.text(t.tour3Title), findsOneWidget);
      await tester.tap(find.text(t.getStarted));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget, reason: 'the tour closes');
      expect(await tourSeen(), isTrue);
      restore();
    });

    testWidgets('done screen and loading outlines ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(
        DoneScreen(title: t.requestSentTitle, body: t.requestSentBody('Dr. Ahmed'), primaryLabel: t.backToExplore, onPrimary: () {}),
        lang,
      ));
      await tester.pumpAndSettle();
      expect(find.text(t.requestSentTitle), findsOneWidget);
      await tester.pumpWidget(_app(const Scaffold(body: SingleChildScrollView(child: SkeletonList())), lang));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SkeletonList), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      restore();
    });

    testWidgets('report sheet needs a reason ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReportSheet(context, memberId: 'm1', title: t.reportMember),
              child: const Text('open'),
            ),
          ),
        ),
        lang,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final send = find.widgetWithText(FilledButton, t.sendReport);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.text(t.reasonNoShow));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
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

    testWidgets('basic details after sign-up, papers later ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(BasicDetailsScreen(profile: _profile('unverified', name: '', phone: null), onSaved: () {}), lang));
      await tester.pumpAndSettle();
      expect(find.text(t.basicsTitle), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text(t.syndicateCard), findsNothing, reason: 'papers are not asked for at sign-up');
      await tester.tap(find.text(t.startUsing));
      await tester.pumpAndSettle();
      expect(find.text(t.required), findsWidgets, reason: 'name and mobile are needed');
      restore();
    });

    testWidgets('post tab asks for papers when not verified ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(GetVerifiedScreen(profile: _profile('unverified'), onChanged: () {}), lang));
      await tester.pumpAndSettle();
      expect(find.text(t.postNeedsVerifyTitle), findsOneWidget);
      await tester.tap(find.text(t.getVerified));
      await tester.pumpAndSettle();
      expect(find.byType(VerifyScreen), findsOneWidget);
      expect(find.text(t.verifyTitle), findsOneWidget);
      expect(find.text(t.syndicateNo), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(VerifyScreen), findsNothing);
      restore();
    });

    testWidgets('post tab while papers are checked, and after a rejection ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(GetVerifiedScreen(profile: _profile('pending'), onChanged: () {}), lang));
      await tester.pumpAndSettle();
      expect(find.text(t.papersCheckingTitle), findsOneWidget);
      expect(find.text(t.getVerified), findsNothing);
      await tester.pumpWidget(_app(GetVerifiedScreen(profile: _profile('rejected'), onChanged: () {}), lang));
      await tester.pumpAndSettle();
      expect(find.text(t.rejectedTitle), findsOneWidget);
      expect(find.text(t.sendAgain), findsOneWidget);
      restore();
    });

    testWidgets('home banner and the verified mark ($lang)', (tester) async {
      await _phone(tester);
      final restore = _ignoreOverflow();
      final t = lookupAppLocalizations(Locale(lang));
      await tester.pumpWidget(_app(
        Scaffold(
          body: Column(children: [
            VerifyBanner(profile: _profile('unverified'), onChanged: () {}),
            VerifyBanner(profile: _profile('approved'), onChanged: () {}),
            const NameWithMark(name: 'Dr. Ahmed Mansour', verified: true),
            const NameWithMark(name: 'Dr. Mona Fathy', verified: false),
          ]),
        ),
        lang,
      ));
      await tester.pumpAndSettle();
      expect(find.text(t.getVerifiedTitle), findsOneWidget, reason: 'only the unverified member sees the banner');
      expect(find.byType(VerifiedMark), findsOneWidget);
      restore();
    });
  }
}
