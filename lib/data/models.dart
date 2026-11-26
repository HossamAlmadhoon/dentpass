enum SlotKind { observe, course, rent, cover }

enum BookingStatus { pending, accepted, declined, cancelled }

enum VerificationStatus { unverified, pending, approved, rejected, suspended }

enum MemberRole { dentist, assistant }

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

DateTime _date(Object? raw) => raw is String ? DateTime.parse(raw).toLocal() : DateTime.now();

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

double? _double(Object? raw) => raw is num ? raw.toDouble() : (raw is String ? double.tryParse(raw) : null);

List<String> _strings(Object? raw) => raw is List ? raw.whereType<String>().toList() : const [];

class Profile {
  Profile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.syndicateNo,
    required this.area,
    required this.status,
    required this.rejectionReason,
    required this.cardPath,
    required this.idPath,
    required this.isAdmin,
    required this.bio,
    required this.avatarPath,
  });

  final String id;
  final String fullName;
  final String? phone;
  final MemberRole role;
  final String? syndicateNo;
  final String? area;
  final VerificationStatus status;
  final String? rejectionReason;
  final String? cardPath;
  final String? idPath;
  final bool isAdmin;
  final String bio;
  final String? avatarPath;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: (m['full_name'] as String?) ?? '',
        phone: m['phone'] as String?,
        role: _enum(MemberRole.values, m['role'], MemberRole.dentist),
        syndicateNo: m['syndicate_no'] as String?,
        area: m['area'] as String?,
        status: _enum(VerificationStatus.values, m['status'], VerificationStatus.unverified),
        rejectionReason: m['rejection_reason'] as String?,
        cardPath: m['card_path'] as String?,
        idPath: m['id_path'] as String?,
        isAdmin: (m['is_admin'] as bool?) ?? false,
        bio: (m['bio'] as String?) ?? '',
        avatarPath: m['avatar_path'] as String?,
      );
}

class Slot {
  Slot({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.kind,
    required this.title,
    required this.description,
    required this.area,
    required this.address,
    required this.startsAt,
    required this.endsAt,
    required this.capacity,
    required this.taken,
    required this.priceEgp,
    required this.needRole,
    required this.photoPath,
    required this.isOpen,
    required this.hostPhone,
    required this.photoPaths,
    required this.lat,
    required this.lng,
    required this.hostRating,
    required this.hostReviews,
    required this.exactLocation,
  });

  final String id;
  final String hostId;
  final String hostName;
  final SlotKind kind;
  final String title;
  final String description;
  final String area;
  final String address; // empty unless you are the host or your booking is accepted
  final DateTime startsAt;
  final DateTime endsAt;
  final int capacity;
  final int taken;
  final int priceEgp;
  final MemberRole? needRole;
  final String? photoPath;
  final bool isOpen;
  final String? hostPhone; // only once your booking is accepted
  final List<String> photoPaths;
  final double? lat; // rounded to about 1 km unless [exactLocation]
  final double? lng;
  final double? hostRating;
  final int hostReviews;
  final bool exactLocation;

  bool get hasLocation => lat != null && lng != null;
  bool get hasEnded => endsAt.isBefore(DateTime.now());

  int get placesLeft => (capacity - taken).clamp(0, capacity);
  bool get isFull => kind != SlotKind.cover && placesLeft == 0;

  factory Slot.fromMap(Map<String, dynamic> m) => Slot(
        id: m['id'] as String,
        hostId: (m['host_id'] as String?) ?? '',
        hostName: (m['host_name'] as String?) ?? '',
        kind: _enum(SlotKind.values, m['kind'], SlotKind.observe),
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        area: (m['area'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        startsAt: _date(m['starts_at']),
        endsAt: _date(m['ends_at']),
        capacity: _int(m['capacity']),
        taken: _int(m['taken']),
        priceEgp: _int(m['price_egp']),
        needRole: m['need_role'] == null ? null : _enum(MemberRole.values, m['need_role'], MemberRole.dentist),
        photoPath: m['photo_path'] as String?,
        isOpen: (m['is_open'] as bool?) ?? true,
        hostPhone: m['host_phone'] as String?,
        photoPaths: () {
          final list = _strings(m['photo_paths']);
          if (list.isNotEmpty) return list;
          final single = m['photo_path'] as String?;
          return single == null ? <String>[] : [single];
        }(),
        lat: _double(m['lat']),
        lng: _double(m['lng']),
        hostRating: _double(m['host_rating']),
        hostReviews: _int(m['host_reviews']),
        exactLocation: (m['exact_location'] as bool?) ?? false,
      );
}

class Booking {
  Booking({
    required this.id,
    required this.slotId,
    required this.status,
    required this.priceEgp,
    required this.feeEgp,
    required this.slot,
  });

  final String id;
  final String slotId;
  final BookingStatus status;
  final int priceEgp;
  final int feeEgp;
  final Slot? slot;

  bool get isActive => status == BookingStatus.pending || status == BookingStatus.accepted;

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'] as String,
        slotId: m['slot_id'] as String,
        status: _enum(BookingStatus.values, m['status'], BookingStatus.pending),
        priceEgp: _int(m['price_egp']),
        feeEgp: _int(m['fee_egp']),
        slot: m['slots'] is Map<String, dynamic> ? Slot.fromMap(m['slots'] as Map<String, dynamic>) : null,
      );
}

/// A slot the signed-in user hosts, with how many requests wait for an answer.
class HostedSlot {
  HostedSlot({required this.slot, required this.pendingCount, required this.totalCount});

  final Slot slot;
  final int pendingCount;
  final int totalCount;

  factory HostedSlot.fromMap(Map<String, dynamic> m) {
    final bookings = (m['bookings'] as List?) ?? const [];
    return HostedSlot(
      slot: Slot.fromMap(m),
      pendingCount: bookings.where((b) => (b as Map)['status'] == 'pending').length,
      totalCount: bookings.length,
    );
  }
}

class SlotRequest {
  SlotRequest({
    required this.id,
    required this.userId,
    required this.rating,
    required this.reviews,
    required this.reviewed,
    required this.status,
    required this.message,
    required this.fullName,
    required this.role,
    required this.phone,
  });

  final String id;
  final String userId;
  final double? rating;
  final int reviews;
  final bool reviewed;
  final BookingStatus status;
  final String message;
  final String fullName;
  final MemberRole role;
  final String? phone;

  factory SlotRequest.fromMap(Map<String, dynamic> m) => SlotRequest(
        id: m['id'] as String,
        userId: (m['user_id'] as String?) ?? '',
        rating: _double(m['rating']),
        reviews: _int(m['reviews']),
        reviewed: (m['reviewed'] as bool?) ?? false,
        status: _enum(BookingStatus.values, m['status'], BookingStatus.pending),
        message: (m['message'] as String?) ?? '',
        fullName: (m['full_name'] as String?) ?? '',
        role: _enum(MemberRole.values, m['role'], MemberRole.dentist),
        phone: m['phone'] as String?,
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.slotId,
    required this.slotTitle,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String? slotId;
  final String slotTitle;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: (m['type'] as String?) ?? '',
        slotId: m['slot_id'] as String?,
        slotTitle: m['slots'] is Map
            ? ((m['slots'] as Map)['title'] as String? ?? '')
            : ((m['slot_title'] as String?) ?? ''),
        read: (m['read'] as bool?) ?? false,
        createdAt: _date(m['created_at']),
      );
}

/// A member's public page.
class Member {
  Member({
    required this.id,
    required this.fullName,
    required this.role,
    required this.area,
    required this.bio,
    required this.avatarPath,
    required this.memberSince,
    required this.rating,
    required this.reviews,
    required this.hosted,
    required this.attended,
  });

  final String id;
  final String fullName;
  final MemberRole role;
  final String area;
  final String bio;
  final String? avatarPath;
  final DateTime memberSince;
  final double? rating;
  final int reviews;
  final int hosted;
  final int attended;

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        id: m['id'] as String,
        fullName: (m['full_name'] as String?) ?? '',
        role: _enum(MemberRole.values, m['role'], MemberRole.dentist),
        area: (m['area'] as String?) ?? '',
        bio: (m['bio'] as String?) ?? '',
        avatarPath: m['avatar_path'] as String?,
        memberSince: _date(m['member_since']),
        rating: _double(m['rating']),
        reviews: _int(m['reviews']),
        hosted: _int(m['hosted']),
        attended: _int(m['attended']),
      );
}

class Review {
  Review({
    required this.id,
    required this.stars,
    required this.comment,
    required this.createdAt,
    required this.slotTitle,
    required this.reviewerId,
    required this.reviewerName,
  });

  final String id;
  final int stars;
  final String comment;
  final DateTime createdAt;
  final String slotTitle;
  final String reviewerId;
  final String reviewerName;

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        id: m['id'] as String,
        stars: _int(m['stars']),
        comment: (m['comment'] as String?) ?? '',
        createdAt: _date(m['created_at']),
        slotTitle: (m['slot_title'] as String?) ?? '',
        reviewerId: (m['reviewer_id'] as String?) ?? '',
        reviewerName: (m['reviewer_name'] as String?) ?? '',
      );
}

/// Numbers on the admin overview.
class AdminOverview {
  AdminOverview(this.values);
  final Map<String, dynamic> values;

  int count(String key) => _int(values[key]);
}

/// What the home screen shows: my next slot, requests waiting, what I host next.
class HomeSummary {
  HomeSummary({required this.next, required this.waiting, required this.hostingNext});

  final NextSlot? next;
  final int waiting;
  final HostingNext? hostingNext;

  factory HomeSummary.fromMap(Map<String, dynamic> m) => HomeSummary(
        next: m['next'] is Map ? NextSlot.fromMap(Map<String, dynamic>.from(m['next'] as Map)) : null,
        waiting: _int(m['waiting']),
        hostingNext: m['hosting_next'] is Map
            ? HostingNext.fromMap(Map<String, dynamic>.from(m['hosting_next'] as Map))
            : null,
      );
}

class NextSlot {
  NextSlot({
    required this.slotId,
    required this.title,
    required this.kind,
    required this.startsAt,
    required this.endsAt,
    required this.area,
    required this.address,
    required this.lat,
    required this.lng,
    required this.hostName,
    required this.hostPhone,
  });

  final String slotId;
  final String title;
  final SlotKind kind;
  final DateTime startsAt;
  final DateTime endsAt;
  final String area;
  final String address;
  final double? lat;
  final double? lng;
  final String hostName;
  final String? hostPhone;

  factory NextSlot.fromMap(Map<String, dynamic> m) => NextSlot(
        slotId: m['slot_id'] as String,
        title: (m['title'] as String?) ?? '',
        kind: _enum(SlotKind.values, m['kind'], SlotKind.observe),
        startsAt: _date(m['starts_at']),
        endsAt: _date(m['ends_at']),
        area: (m['area'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        lat: _double(m['lat']),
        lng: _double(m['lng']),
        hostName: (m['host_name'] as String?) ?? '',
        hostPhone: m['host_phone'] as String?,
      );
}

class HostingNext {
  HostingNext({required this.slotId, required this.title, required this.startsAt, required this.accepted});

  final String slotId;
  final String title;
  final DateTime startsAt;
  final int accepted;

  factory HostingNext.fromMap(Map<String, dynamic> m) => HostingNext(
        slotId: m['slot_id'] as String,
        title: (m['title'] as String?) ?? '',
        startsAt: _date(m['starts_at']),
        accepted: _int(m['accepted']),
      );
}

enum ReportReason { noShow, unsafe, fake, payment, behaviour, other }

String reportReasonKey(ReportReason r) => switch (r) {
      ReportReason.noShow => 'no_show',
      ReportReason.unsafe => 'unsafe',
      ReportReason.fake => 'fake',
      ReportReason.payment => 'payment',
      ReportReason.behaviour => 'behaviour',
      ReportReason.other => 'other',
    };

ReportReason reportReasonFrom(String? key) =>
    ReportReason.values.firstWhere((r) => reportReasonKey(r) == key, orElse: () => ReportReason.other);

class ReportItem {
  ReportItem({
    required this.id,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    required this.reporterName,
    required this.memberId,
    required this.memberName,
    required this.slotId,
    required this.slotTitle,
  });

  final String id;
  final ReportReason reason;
  final String details;
  final String status;
  final DateTime createdAt;
  final String reporterName;
  final String? memberId;
  final String memberName;
  final String? slotId;
  final String slotTitle;

  factory ReportItem.fromMap(Map<String, dynamic> m) => ReportItem(
        id: m['id'] as String,
        reason: reportReasonFrom(m['reason'] as String?),
        details: (m['details'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'open',
        createdAt: _date(m['created_at']),
        reporterName: (m['reporter_name'] as String?) ?? '',
        memberId: m['member_id'] as String?,
        memberName: (m['member_name'] as String?) ?? '',
        slotId: m['slot_id'] as String?,
        slotTitle: (m['slot_title'] as String?) ?? '',
      );
}

class SlotAlert {
  SlotAlert({required this.id, required this.kinds, required this.area});

  final String id;
  final List<SlotKind>? kinds; // null = all types
  final String? area; // null = all areas

  factory SlotAlert.fromMap(Map<String, dynamic> m) => SlotAlert(
        id: m['id'] as String,
        kinds: m['kinds'] is List
            ? (m['kinds'] as List).map((k) => _enum(SlotKind.values, k, SlotKind.observe)).toList()
            : null,
        area: m['area'] as String?,
      );
}

class AppSettings {
  AppSettings({required this.feePercent, required this.supportWhatsapp});

  final int feePercent;
  final String? supportWhatsapp;

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        feePercent: _int(m['fee_percent']),
        supportWhatsapp: m['support_whatsapp'] as String?,
      );
}
