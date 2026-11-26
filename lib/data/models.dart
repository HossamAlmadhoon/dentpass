enum SlotKind { observe, course, rent, cover }

enum BookingStatus { pending, accepted, declined, cancelled }

enum VerificationStatus { unverified, pending, approved, rejected }

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
    required this.status,
    required this.message,
    required this.fullName,
    required this.role,
    required this.phone,
  });

  final String id;
  final BookingStatus status;
  final String message;
  final String fullName;
  final MemberRole role;
  final String? phone;

  factory SlotRequest.fromMap(Map<String, dynamic> m) => SlotRequest(
        id: m['id'] as String,
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
        slotTitle: m['slots'] is Map ? ((m['slots'] as Map)['title'] as String? ?? '') : '',
        read: (m['read'] as bool?) ?? false,
        createdAt: _date(m['created_at']),
      );
}
