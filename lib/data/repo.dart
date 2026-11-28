import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/platform/push.dart';

/// Every call to Supabase lives here, so screens stay simple.
/// The database rules (supabase/migrations) decide who may read or change what.
class Repo {
  SupabaseClient get db => Supabase.instance.client;

  String get uid => db.auth.currentUser!.id;

  // ---------------------------------------------------------------- auth
  /// On the web version, the confirmation email brings people back to the same page.
  Future<AuthResponse> signUp(String email, String password) => db.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : null,
      );

  Future<AuthResponse> signIn(String email, String password) =>
      db.auth.signInWithPassword(email: email, password: password);

  /// Signs out; this phone stops getting the member's notifications first.
  Future<void> signOut() async {
    try {
      final device = await pushCurrent();
      if (device != null) await removePushDevice(device.endpoint);
    } catch (_) {}
    await db.auth.signOut();
  }

  /// Emails a link to set a new password. On the web it brings people back with ?reset=1.
  Future<void> sendPasswordReset(String email) => db.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? '${Uri.base.origin}${Uri.base.path}?reset=1' : null,
      );

  Future<void> setPassword(String password) async {
    await db.auth.updateUser(UserAttributes(password: password));
  }

  // ---------------------------------------------------------------- profile
  Future<Profile> myProfile() async {
    final row = await db.from('profiles').select().eq('id', uid).single();
    return Profile.fromMap(row);
  }

  /// Uploads an image to `bucket/user-id/name` and returns its path.
  /// [replace] overwrites a file with the same name (used for documents people re-send).
  Future<String> uploadImage(String bucket, String name, XFile file, {bool replace = false}) async {
    final bytes = await file.readAsBytes();
    final path = '$uid/$name';
    await db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: replace, contentType: _imageType(file)),
        );
    return path;
  }

  static String _imageType(XFile file) {
    final type = file.mimeType;
    if (type != null && type.startsWith('image/')) return type;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> submitVerification({
    required String fullName,
    required String phone,
    required MemberRole role,
    required String? syndicateNo,
    required String area,
    required String? cardPath,
    required String idPath,
  }) async {
    await db.from('profiles').update({
      'full_name': fullName,
      'phone': phone,
      'role': role.name,
      'syndicate_no': role == MemberRole.dentist ? syndicateNo : null,
      'area': area,
      'card_path': role == MemberRole.dentist ? cardPath : null,
      'id_path': idPath,
      'status': 'pending',
    }).eq('id', uid);
  }

  /// The few details needed to start: name, mobile, role and area. Papers can follow later.
  Future<void> saveBasics({
    required String fullName,
    required String phone,
    required MemberRole role,
    required String area,
  }) async {
    await db.from('profiles').update({
      'full_name': fullName,
      'phone': phone,
      'role': role.name,
      'area': area,
      'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }

  // ---------------------------------------------------------------- slots
  Future<List<Slot>> feed({
    List<SlotKind>? kinds,
    String? area,
    String? query,
    DateTime? from,
    DateTime? to,
    String? hostId,
  }) async {
    final rows = await db.rpc('get_feed', params: {
      'p_kind': kinds?.map((k) => k.name).toList(),
      'p_area': area,
      'p_query': (query == null || query.trim().isEmpty) ? null : query.trim(),
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
      'p_host': hostId,
    });
    return (rows as List).map((r) => Slot.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<Slot?> slot(String id) async {
    final rows = await db.rpc('get_slot', params: {'p_slot': id}) as List;
    return rows.isEmpty ? null : Slot.fromMap(rows.first as Map<String, dynamic>);
  }

  /// Posts a slot and returns its id.
  Future<String> createSlot({
    required SlotKind kind,
    required String title,
    required String description,
    required String area,
    required String address,
    required DateTime startsAt,
    required DateTime endsAt,
    required int capacity,
    required int priceEgp,
    required MemberRole? needRole,
    required List<String> photoPaths,
    required double? lat,
    required double? lng,
    bool negotiable = false,
  }) async {
    final row = await db.from('slots').insert({
      'negotiable': negotiable,
      'host_id': uid,
      'kind': kind.name,
      'title': title,
      'description': description,
      'area': area,
      'address': address,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'capacity': capacity,
      'price_egp': priceEgp,
      'need_role': kind == SlotKind.cover ? (needRole ?? MemberRole.dentist).name : null,
      'photo_path': photoPaths.isEmpty ? null : photoPaths.first,
      'photo_paths': photoPaths,
      'lat': lat,
      'lng': lng,
    }).select('id').single();
    return row['id'] as String;
  }

  /// Saves a host's edits. People with a request are told automatically when
  /// the time, place or price changes.
  Future<void> updateSlot(
    String slotId, {
    required String title,
    required String description,
    required String area,
    required String address,
    required DateTime startsAt,
    required DateTime endsAt,
    required int capacity,
    required int priceEgp,
    required MemberRole? needRole,
    required List<String> photoPaths,
    required double? lat,
    required double? lng,
    bool negotiable = false,
  }) async {
    await db.from('slots').update({
      'negotiable': negotiable,
      'title': title,
      'description': description,
      'area': area,
      'address': address,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'capacity': capacity,
      'price_egp': priceEgp,
      if (needRole != null) 'need_role': needRole.name,
      'photo_path': photoPaths.isEmpty ? null : photoPaths.first,
      'photo_paths': photoPaths,
      'lat': lat,
      'lng': lng,
    }).eq('id', slotId);
  }

  /// Deletes a slot. Everyone with a request is told it was cancelled.
  Future<void> deleteSlot(String slotId, {List<String> photoPaths = const []}) async {
    await db.from('slots').delete().eq('id', slotId);
    await removeSlotPhotos(photoPaths);
  }

  /// Removes photos the host took off a slot. Failures are ignored: an unused file does no harm.
  Future<void> removeSlotPhotos(List<String> paths) async {
    final own = paths.where((p) => p.startsWith('$uid/')).toList();
    if (own.isEmpty) return;
    try {
      await db.storage.from('slot-photos').remove(own);
    } catch (_) {}
  }

  Future<void> setSlotOpen(String slotId, bool open) async {
    await db.from('slots').update({'is_open': open}).eq('id', slotId);
  }

  String photoUrl(String path) => db.storage.from('slot-photos').getPublicUrl(path);

  Future<List<HostedSlot>> myPosts() async {
    final rows = await db
        .from('slots')
        .select('*, bookings(status)')
        .eq('host_id', uid)
        .order('starts_at', ascending: false);
    return rows.map(HostedSlot.fromMap).toList();
  }

  // ---------------------------------------------------------------- bookings
  Future<int> feePercent() async {
    final row = await db.from('app_settings').select('fee_percent').single();
    return (row['fee_percent'] as num).round();
  }

  Future<Booking?> myBookingFor(String slotId) async {
    final row = await db
        .from('bookings')
        .select()
        .eq('slot_id', slotId)
        .eq('user_id', uid)
        .maybeSingle();
    return row == null ? null : Booking.fromMap(row);
  }

  /// [offer] is the price this person suggests, when the host allows offers.
  Future<void> book(String slotId, String message, {int? offer}) async {
    await db.rpc('book_slot', params: {'p_slot': slotId, 'p_message': message, if (offer != null) 'p_offer': offer});
  }

  /// "I've paid": tells the host the money was sent.
  Future<void> markPaid(String bookingId) async {
    await db.rpc('mark_paid', params: {'p_booking': bookingId});
  }

  Future<void> cancelBooking(String bookingId) async {
    await db.rpc('cancel_booking', params: {'p_booking': bookingId});
  }

  Future<void> respond(String bookingId, bool accept) async {
    await db.rpc('respond_booking', params: {'p_booking': bookingId, 'p_accept': accept});
  }

  Future<List<Booking>> myBookings() async {
    final rows = await db
        .from('bookings')
        .select('*, slots(*)')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return rows.map(Booking.fromMap).toList();
  }

  Future<List<SlotRequest>> slotRequests(String slotId) async {
    final rows = await db.rpc('get_slot_requests', params: {'p_slot': slotId}) as List;
    return rows.map((r) => SlotRequest.fromMap(r as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------- members and ratings
  Future<Member?> member(String userId) async {
    final rows = await db.rpc('get_member', params: {'p_user': userId}) as List;
    return rows.isEmpty ? null : Member.fromMap(rows.first as Map<String, dynamic>);
  }

  Future<List<Review>> reviewsOf(String userId) async {
    final rows = await db.rpc('get_reviews', params: {'p_user': userId}) as List;
    return rows.map((r) => Review.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> submitReview(String bookingId, int stars, String comment) async {
    await db.rpc('submit_review', params: {'p_booking': bookingId, 'p_stars': stars, 'p_comment': comment});
  }

  /// Bookings the signed-in member has already rated.
  Future<Set<String>> myRatedBookingIds() async {
    final rows = await db.from('reviews').select('booking_id').eq('reviewer_id', uid);
    return rows.map((r) => r['booking_id']).whereType<String>().toSet();
  }

  String avatarUrl(String path) => db.storage.from('avatars').getPublicUrl(path);

  Future<void> updateProfile({
    required String phone,
    required String area,
    required String bio,
    required String? avatarPath,
    String? instapay,
  }) async {
    await db.from('profiles').update({
      'phone': phone,
      'area': area,
      'bio': bio,
      'avatar_path': avatarPath,
      'instapay': (instapay ?? '').trim().isEmpty ? null : instapay!.trim(),
    }).eq('id', uid);
  }

  /// Where this member receives payments as a host. Empty clears it.
  Future<void> saveInstapay(String value) async {
    await db.from('profiles').update({'instapay': value.trim().isEmpty ? null : value.trim()}).eq('id', uid);
  }

  /// Removes the member's files, then the account and everything linked to it.
  Future<void> deleteMyAccount() async {
    for (final bucket in ['verification', 'slot-photos', 'avatars']) {
      try {
        final files = await db.storage.from(bucket).list(path: uid);
        final paths = files.map((f) => '$uid/${f.name}').toList();
        if (paths.isNotEmpty) await db.storage.from(bucket).remove(paths);
      } catch (_) {}
    }
    await db.rpc('delete_my_account');
    await db.auth.signOut();
  }

  // ---------------------------------------------------------------- home, terms, settings
  Future<HomeSummary> home() async {
    final data = await db.rpc('my_home');
    return HomeSummary.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<void> acceptTerms() async {
    await db.from('profiles').update({'accepted_terms_at': DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
  }

  /// Remembers the language for phone notifications. Ignored when signed out.
  Future<void> saveLanguage(String code) async {
    if (db.auth.currentUser == null) return;
    try {
      await db.from('profiles').update({'lang': code == 'en' ? 'en' : 'ar'}).eq('id', uid);
    } catch (_) {}
  }

  Future<AppSettings> settings() async {
    final row = await db.from('app_settings').select('fee_percent, support_whatsapp, instapay_handle').single();
    return AppSettings.fromMap(row);
  }

  Future<void> saveSettings({required int feePercent, required String supportWhatsapp, String? dentpassInstapay}) async {
    await db.from('app_settings').update({
      'fee_percent': feePercent,
      'support_whatsapp': supportWhatsapp.isEmpty ? null : supportWhatsapp,
      'instapay_handle': (dentpassInstapay ?? '').trim().isEmpty ? null : dentpassInstapay!.trim(),
    }).eq('id', true);
  }

  // ---------------------------------------------------------------- DentPass fees (hosts pay monthly)
  static String _monthKey(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}-01';

  Future<List<FeeMonth>> hostStatement() async {
    final rows = await db.rpc('host_statement') as List;
    return rows.map((r) => FeeMonth.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> markFeesPaid(DateTime month) async {
    await db.rpc('mark_fees_paid', params: {'p_month': _monthKey(month)});
  }

  Future<List<FeeMonth>> adminFees() async {
    final rows = await db.rpc('admin_fees') as List;
    return rows.map((r) => FeeMonth.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> confirmFees(String hostId, DateTime month) async {
    await db.rpc('confirm_fees', params: {'p_host': hostId, 'p_month': _monthKey(month)});
  }

  // ---------------------------------------------------------------- reports and alerts
  Future<void> report({String? memberId, String? slotId, required ReportReason reason, required String details}) async {
    await db.from('reports').insert({
      'reporter_id': uid,
      'member_id': memberId,
      'slot_id': slotId,
      'reason': reportReasonKey(reason),
      'details': details,
    });
  }

  Future<List<ReportItem>> adminReports({required bool open}) async {
    final rows = await db.rpc('admin_reports', params: {'p_status': open ? 'open' : 'closed'}) as List;
    return rows.map((r) => ReportItem.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> closeReport(String id) async {
    await db.from('reports').update({'status': 'closed', 'closed_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<List<SlotAlert>> alerts() async {
    final rows = await db.from('slot_alerts').select().eq('user_id', uid).order('created_at');
    return rows.map(SlotAlert.fromMap).toList();
  }

  /// Saves an alert; saving the same one twice is fine.
  Future<void> addAlert({List<SlotKind>? kinds, String? area}) async {
    try {
      await db.from('slot_alerts').insert({
        'user_id': uid,
        'kinds': kinds?.map((k) => k.name).toList(),
        'area': area,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // already saved
    }
  }

  Future<void> removeAlert(String id) async {
    await db.from('slot_alerts').delete().eq('id', id);
  }

  // ---------------------------------------------------------------- phone notifications
  Future<void> savePushDevice({required String endpoint, required String p256dh, required String auth, required String lang}) async {
    await db.rpc('save_push_subscription', params: {
      'p_endpoint': endpoint,
      'p_p256dh': p256dh,
      'p_auth': auth,
      'p_lang': lang,
    });
  }

  Future<void> removePushDevice(String endpoint) async {
    await db.rpc('remove_push_subscription', params: {'p_endpoint': endpoint});
  }

  // ---------------------------------------------------------------- notifications
  Future<List<AppNotification>> notifications() async {
    final rows = await db
        .from('notifications')
        .select('*, slots(title)')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> unreadCount() async {
    final rows = await db.from('notifications').select('id').eq('user_id', uid).eq('read', false);
    return rows.length;
  }

  Future<void> markAllRead() async {
    await db.from('notifications').update({'read': true}).eq('user_id', uid).eq('read', false);
  }

  // ---------------------------------------------------------------- admin
  Future<List<Profile>> pendingMembers() async {
    final rows = await db
        .from('profiles')
        .select()
        .eq('status', 'pending')
        .order('submitted_at', ascending: true);
    return rows.map(Profile.fromMap).toList();
  }

  Future<List<Profile>> members({VerificationStatus? status, String? query}) async {
    var q = db.from('profiles').select();
    if (status != null) q = q.eq('status', status.name);
    // People who signed up but never filled in their details are left out
    if (status == VerificationStatus.unverified) q = q.neq('full_name', '');
    final text = query?.trim() ?? '';
    if (text.isNotEmpty) {
      final safe = text.replaceAll(RegExp(r'[,()%]'), ' ');
      q = q.or('full_name.ilike.%$safe%,phone.ilike.%$safe%');
    }
    final rows = await q.order('created_at', ascending: false).limit(200);
    return rows.map(Profile.fromMap).toList();
  }

  Future<void> setMemberStatus(String userId, {required bool suspend, String? reason}) async {
    await db.rpc('set_member_status', params: {'p_user': userId, 'p_suspend': suspend, 'p_reason': reason});
  }

  Future<AdminOverview> adminOverview() async {
    final data = await db.rpc('admin_overview');
    return AdminOverview(Map<String, dynamic>.from(data as Map));
  }

  /// Every upcoming slot, with the host's name, for admins.
  Future<List<Slot>> adminSlots() async {
    final rows = await db
        .from('slots')
        .select('*, profiles!slots_host_id_fkey(full_name)')
        .gte('ends_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at')
        .limit(300);
    return rows.map((r) {
      final host = r['profiles'];
      return Slot.fromMap({...r, 'host_name': host is Map ? host['full_name'] : ''});
    }).toList();
  }

  Future<String> verificationFileUrl(String path) =>
      db.storage.from('verification').createSignedUrl(path, 600);

  Future<void> setVerification(String userId, bool approve, {String? reason}) async {
    await db.rpc('set_verification', params: {
      'p_user': userId,
      'p_approve': approve,
      'p_reason': reason,
    });
  }
}

/// Screenshot tests swap this for one with sample data.
Repo repo = Repo();
