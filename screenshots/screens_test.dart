// Renders the main screens with sample data, so the design can be reviewed as pictures.
// Run in CI by .github/workflows/screens.yml: flutter test screenshots --update-goldens
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/data/repo.dart';
import 'package:dentpass/l10n/app_localizations.dart';
import 'package:dentpass/screens/basic_details_screen.dart';
import 'package:dentpass/screens/home_shell.dart';
import 'package:dentpass/screens/info_screens.dart';
import 'package:dentpass/screens/manage_slot_screen.dart';
import 'package:dentpass/screens/member_screen.dart';
import 'package:dentpass/screens/notifications_screen.dart';
import 'package:dentpass/screens/sign_in_screen.dart';
import 'package:dentpass/screens/slot_detail_screen.dart';
import 'package:dentpass/theme.dart';

final _now = DateTime.now();
String _at(int days, int hour) =>
    DateTime(_now.year, _now.month, _now.day + days, hour).toUtc().toIso8601String();

Map<String, dynamic> _slotMap(String id, String kind, String title,
        {String host = 'د. أحمد منصور', String hostId = 'h1', String area = 'heliopolis', int day = 2,
        int hour = 10, int len = 4, int capacity = 3, int taken = 1, int price = 1500, String? needRole,
        String description = '', String address = '', String? phone, double? rating = 4.8, int reviews = 12}) =>
    {
      'id': id,
      'host_id': hostId,
      'host_name': host,
      'kind': kind,
      'title': title,
      'description': description,
      'area': area,
      'address': address,
      'starts_at': _at(day, hour),
      'ends_at': _at(day, hour + len),
      'capacity': capacity,
      'taken': taken,
      'price_egp': price,
      'need_role': needRole,
      'is_open': true,
      'host_phone': phone,
      'photo_paths': <String>[],
      'host_rating': rating,
      'host_reviews': reviews,
    };

final _slots = [
  _slotMap('s1', 'observe', 'زراعة فك كامل مع تحميل فوري',
      description: 'حالة All-on-4 لمريض 58 سنة. سنشرح التخطيط الرقمي قبل البدء، ثم الجراحة كاملة، ثم تركيب التركيبة المؤقتة في نفس اليوم. مناسب لمن بدأ الزراعة.',
      day: 2, capacity: 3, taken: 1, price: 1500),
  _slotMap('s2', 'rent', 'كرسي مجهز بالكامل في عيادة بالمعادي',
      host: 'د. منى فتحي', hostId: 'h2', area: 'maadi', day: 1, hour: 9, len: 8, capacity: 1, taken: 0, price: 900,
      rating: 4.6, reviews: 5),
  _slotMap('s3', 'cover', 'مطلوب مساعدة لشيفت مسائي',
      host: 'د. كريم السيد', hostId: 'h3', area: 'nasr_city', day: 0, hour: 17, len: 5, capacity: 1, taken: 0,
      price: 400, needRole: 'assistant', rating: null, reviews: 0),
  _slotMap('s4', 'course', 'كورس الحشو التجميلي الخلفي - يومين عملي',
      host: 'د. هالة رضا', hostId: 'h4', area: 'dokki', day: 6, hour: 10, len: 6, capacity: 12, taken: 9, price: 4500,
      rating: 4.9, reviews: 31),
];

Profile _me({String status = 'approved'}) => Profile.fromMap({
      'id': 'me',
      'full_name': 'د. سارة عادل',
      'phone': '01012345678',
      'role': 'dentist',
      'syndicate_no': '45821',
      'area': 'heliopolis',
      'status': status,
      'is_admin': false,
      'bio': 'طبيبة أسنان عامة، مهتمة بالزراعة والتجميل.',
    });

/// Sample answers for every call the reviewed screens make.
class FakeRepo extends Repo {
  FakeRepo({this.booking});
  final Map<String, dynamic>? booking;

  @override
  String get uid => 'me';

  @override
  Future<List<Slot>> feed({List<SlotKind>? kinds, String? area, String? query, DateTime? from, DateTime? to, String? hostId}) async =>
      [for (final s in _slots) if (hostId == null || s['host_id'] == hostId) Slot.fromMap(s)];

  @override
  Future<Slot?> slot(String id) async {
    final s = Map<String, dynamic>.from(_slots.firstWhere((s) => s['id'] == id, orElse: () => _slots.first));
    if (booking?['status'] == 'accepted') {
      s['address'] = '12 شارع الثورة، الدور الثالث';
      s['host_phone'] = '01099990000';
    }
    return Slot.fromMap(s);
  }

  @override
  Future<int> unreadCount() async => 3;

  @override
  Future<HomeSummary> home() async => HomeSummary.fromMap({
        'next': {
          'slot_id': 's1',
          'title': 'زراعة فك كامل مع تحميل فوري',
          'kind': 'observe',
          'starts_at': _at(2, 10),
          'ends_at': _at(2, 14),
          'area': 'heliopolis',
          'address': '12 شارع الثورة',
          'host_name': 'د. أحمد منصور',
          'host_phone': '01099990000',
        },
        'waiting': 1,
        'hosting_next': {'slot_id': 's2', 'title': 'كرسي مجهز بالكامل', 'starts_at': _at(1, 9), 'accepted': 1},
      });

  @override
  Future<int> feePercent() async => 10;

  @override
  Future<Booking?> myBookingFor(String slotId) async => booking == null ? null : Booking.fromMap(booking!);

  @override
  Future<Set<String>> myRatedBookingIds() async => {};

  @override
  Future<List<Booking>> myBookings() async => [
        Booking.fromMap({'id': 'b1', 'slot_id': 's1', 'status': 'accepted', 'price_egp': 1500, 'fee_egp': 150, 'slots': _slots[0]}),
        Booking.fromMap({'id': 'b2', 'slot_id': 's4', 'status': 'pending', 'price_egp': 4500, 'fee_egp': 450, 'slots': _slots[3]}),
        Booking.fromMap({
          'id': 'b3', 'slot_id': 'old', 'status': 'accepted', 'price_egp': 800, 'fee_egp': 80,
          'slots': _slotMap('old', 'observe', 'رفع جيوب أنفية مغلق', day: -12),
        }),
      ];

  @override
  Future<List<HostedSlot>> myPosts() async => [
        HostedSlot.fromMap({..._slots[1], 'bookings': [{'status': 'pending'}, {'status': 'accepted'}]}),
      ];

  @override
  Future<List<SlotRequest>> slotRequests(String slotId) async => [
        SlotRequest.fromMap({
          'id': 'r1', 'user_id': 'u1', 'status': 'pending', 'message': 'أعمل في الزراعة منذ سنتين وأريد رؤية التحميل الفوري.',
          'full_name': 'د. يوسف حمدي', 'role': 'dentist', 'rating': 4.7, 'reviews': 6, 'reviewed': false, 'verified': true,
          'price_egp': 1500, 'fee_egp': 150, 'created_at': _at(-1, 12),
        }),
        SlotRequest.fromMap({
          'id': 'r2', 'user_id': 'u2', 'status': 'pending', 'message': '',
          'full_name': 'د. نورا سمير', 'role': 'dentist', 'rating': null, 'reviews': 0, 'reviewed': false, 'verified': false,
          'price_egp': 1500, 'fee_egp': 150, 'created_at': _at(0, 8),
        }),
        SlotRequest.fromMap({
          'id': 'r3', 'user_id': 'u3', 'status': 'accepted', 'message': 'شكراً',
          'full_name': 'د. عمر خالد', 'role': 'dentist', 'phone': '01122223333', 'rating': 5, 'reviews': 2,
          'reviewed': false, 'verified': true, 'price_egp': 1500, 'fee_egp': 150, 'created_at': _at(-2, 12),
        }),
      ];

  @override
  Future<Member?> member(String userId) async => Member.fromMap({
        'id': userId,
        'full_name': userId == 'me' ? 'د. سارة عادل' : 'د. أحمد منصور',
        'role': 'dentist',
        'area': 'heliopolis',
        'bio': userId == 'me' ? 'طبيبة أسنان عامة، مهتمة بالزراعة والتجميل.' : 'استشاري زراعة الأسنان. أستقبل أطباء لمشاهدة الحالات كل أسبوع.',
        'member_since': '2026-08-01T00:00:00Z',
        'rating': 4.8,
        'reviews': 12,
        'hosted': 18,
        'attended': 3,
        'verified': true,
      });

  @override
  Future<List<Review>> reviewsOf(String userId) async => [
        Review.fromMap({
          'id': 'v1', 'stars': 5, 'comment': 'شرح ممتاز وكل خطوة واضحة. العيادة منظمة جداً.',
          'created_at': _at(-5, 12), 'slot_title': 'زراعة فورية', 'reviewer_id': 'u1', 'reviewer_name': 'د. يوسف حمدي',
        }),
        Review.fromMap({
          'id': 'v2', 'stars': 4, 'comment': 'تجربة مفيدة، تأخر البدء نصف ساعة.',
          'created_at': _at(-20, 12), 'slot_title': 'رفع جيوب', 'reviewer_id': 'u2', 'reviewer_name': 'د. نورا سمير',
        }),
      ];

  @override
  Future<List<AppNotification>> notifications() async => [
        for (final (i, type, read) in [
          (0, 'booking_accepted', false),
          (1, 'new_slot', false),
          (2, 'booking_requested', false),
          (3, 'reminder', true),
          (4, 'review_received', true),
        ])
          AppNotification.fromMap({
            'id': 'n$i', 'type': type, 'slot_id': 's1', 'slot_title': 'زراعة فك كامل مع تحميل فوري',
            'read': read, 'created_at': _at(-i, 9),
          }),
      ];

  @override
  Future<void> markAllRead() async {}

  @override
  Future<List<SlotAlert>> alerts() async => [];

  @override
  Future<void> saveLanguage(String code) async {}
}

Future<void> _loadFonts() async {
  final plex = FontLoader('Plex');
  for (final f in Directory('screenshots/fonts').listSync().whereType<File>()) {
    if (f.path.endsWith('.ttf')) plex.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await plex.load();
  final iconFile = File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
  await icons.load();
}

final _shot = GlobalKey();

Widget _app(Widget home, String lang) => RepaintBoundary(
      key: _shot,
      // A new key each time, so nothing from the previous picture (an open sheet) stays on screen
      child: MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(fontFamily: 'Plex'),
        locale: Locale(lang),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    );

Future<void> _show(WidgetTester tester, String name, Widget home,
    {String lang = 'ar', double height = 844, Future<void> Function()? then}) async {
  tester.view.physicalSize = Size(390 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(_app(home, lang));
  await tester.pumpAndSettle();
  if (then != null) {
    await then();
    await tester.pumpAndSettle();
  }
  await expectLater(find.byKey(_shot), matchesGoldenFile('out/$name.png'));
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({'welcome_tour_seen_v1': true});
    repo = FakeRepo();
  });
  tearDown(() {
    FlutterError.onError = FlutterError.presentError;
  });

  // Small layout overflows still produce a picture; they're listed in the log instead of failing.
  void tolerant() {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) {
        // ignore: avoid_print
        print('OVERFLOW: ${d.exceptionAsString().split('\n').first}');
        return;
      }
      original?.call(d);
    };
  }

  testWidgets('01 sign in', (t) async {
    tolerant();
    await _show(t, '01_sign_in_ar', const SignInScreen());
    await _show(t, '01_sign_in_en', const SignInScreen(), lang: 'en');
  });

  testWidgets('02 basic details', (t) async {
    tolerant();
    await _show(t, '02_basic_details', BasicDetailsScreen(profile: _me(status: 'unverified'), onSaved: () {}));
  });

  testWidgets('03 home', (t) async {
    tolerant();
    await _show(t, '03_home', HomeShell(profile: _me(), onProfileChanged: () {}));
    await _show(t, '03_home_long', HomeShell(profile: _me(), onProfileChanged: () {}), height: 2000);
    await _show(t, '03_home_en', HomeShell(profile: _me(), onProfileChanged: () {}), lang: 'en', height: 2000);
    await _show(t, '03_home_unverified', HomeShell(profile: _me(status: 'unverified'), onProfileChanged: () {}), height: 1300);
  });

  testWidgets('04 slot', (t) async {
    tolerant();
    await _show(t, '04_slot', SlotDetailScreen(slotId: 's1', profile: _me()), height: 1100);
    await _show(t, '04_slot_book_sheet', SlotDetailScreen(slotId: 's1', profile: _me()),
        then: () => t.tap(find.byType(FilledButton).last));
    repo = FakeRepo(booking: {'id': 'b2', 'slot_id': 's1', 'status': 'pending', 'price_egp': 1500, 'fee_egp': 150});
    await _show(t, '04_slot_pending', SlotDetailScreen(slotId: 's1', profile: _me()));
    repo = FakeRepo(booking: {'id': 'b1', 'slot_id': 's1', 'status': 'accepted', 'price_egp': 1500, 'fee_egp': 150});
    await _show(t, '04_slot_accepted', SlotDetailScreen(slotId: 's1', profile: _me()), height: 1100);
    repo = FakeRepo();
    await _show(t, '04_slot_cover', SlotDetailScreen(slotId: 's3', profile: _me()));
  });

  testWidgets('05 tabs', (t) async {
    tolerant();
    Future<void> tab(int i) => t.tap(find.byType(NavigationDestination).at(i));
    await _show(t, '05_post', HomeShell(profile: _me(), onProfileChanged: () {}), height: 1800, then: () => tab(1));
    await _show(t, '05_post_unverified', HomeShell(profile: _me(status: 'unverified'), onProfileChanged: () {}),
        then: () => tab(1));
    await _show(t, '05_bookings', HomeShell(profile: _me(), onProfileChanged: () {}), then: () => tab(2));
    await _show(t, '05_bookings_posts', HomeShell(profile: _me(), onProfileChanged: () {}), then: () async {
      await tab(2);
      await t.pumpAndSettle();
      await t.tap(find.byType(Tab).last);
    });
    await _show(t, '05_profile', HomeShell(profile: _me(), onProfileChanged: () {}), height: 1500, then: () => tab(3));
  });

  testWidgets('06 more', (t) async {
    tolerant();
    await _show(t, '06_manage_requests', ManageSlotScreen(slotId: 's1', profile: _me()), height: 1300);
    await _show(t, '06_member', MemberScreen(userId: 'h1', viewer: _me()), height: 1400);
    await _show(t, '06_notifications', NotificationsScreen(profile: _me()));
    await _show(t, '06_tour', const WelcomeTour());
  });
}
