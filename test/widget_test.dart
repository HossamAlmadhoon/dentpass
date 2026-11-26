import 'package:flutter_test/flutter_test.dart';

import 'package:dentpass/data/models.dart';
import 'package:dentpass/ui/format.dart';

void main() {
  test('initials skip the Dr. title', () {
    expect(initials('Dr. Mariam Adel'), 'MA');
    expect(initials('Nour Dental'), 'ND');
    expect(initials(''), '?');
  });

  test('a seat slot is full when every place is taken', () {
    final s = Slot.fromMap({
      'id': '1',
      'kind': 'observe',
      'title': 'Implant case',
      'starts_at': '2030-01-01T08:00:00Z',
      'ends_at': '2030-01-01T12:00:00Z',
      'capacity': 3,
      'taken': 3,
      'price_egp': 1000,
    });
    expect(s.isFull, isTrue);
    expect(s.placesLeft, 0);
  });

  test('a cover slot is never shown as full', () {
    final s = Slot.fromMap({
      'id': '2',
      'kind': 'cover',
      'title': 'Evening shift',
      'starts_at': '2030-01-01T14:00:00Z',
      'ends_at': '2030-01-01T20:00:00Z',
      'capacity': 1,
      'taken': 1,
      'need_role': 'dentist',
    });
    expect(s.isFull, isFalse);
    expect(s.needRole, MemberRole.dentist);
  });
}
