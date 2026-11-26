import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dentpass/data/models.dart';

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

  Future<void> signOut() => db.auth.signOut();

  // ---------------------------------------------------------------- profile
  Future<Profile> myProfile() async {
    final row = await db.from('profiles').select().eq('id', uid).single();
    return Profile.fromMap(row);
  }

  /// Uploads an image to `bucket/user-id/name` and returns its path.
  Future<String> uploadImage(String bucket, String name, XFile file) async {
    final bytes = await file.readAsBytes();
    final path = '$uid/$name';
    await db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: file.mimeType ?? 'image/jpeg'),
        );
    return path;
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

  // ---------------------------------------------------------------- slots
  Future<List<Slot>> feed({List<SlotKind>? kinds, String? area}) async {
    final rows = await db.rpc('get_feed', params: {
      'p_kind': kinds?.map((k) => k.name).toList(),
      'p_area': area,
    });
    return (rows as List).map((r) => Slot.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<Slot?> slot(String id) async {
    final rows = await db.rpc('get_slot', params: {'p_slot': id}) as List;
    return rows.isEmpty ? null : Slot.fromMap(rows.first as Map<String, dynamic>);
  }

  Future<void> createSlot({
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
    required String? photoPath,
  }) async {
    await db.from('slots').insert({
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
      'photo_path': photoPath,
    });
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

  Future<void> book(String slotId, String message) async {
    await db.rpc('book_slot', params: {'p_slot': slotId, 'p_message': message});
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

final repo = Repo();
