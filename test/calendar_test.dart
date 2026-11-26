import 'package:flutter_test/flutter_test.dart';

import 'package:dentpass/services/calendar.dart';

void main() {
  test('calendar file has the event in UTC with a reminder', () {
    final ics = buildIcs(
      id: 's1',
      title: 'Implant case, Heliopolis',
      start: DateTime.utc(2030, 3, 2, 8),
      end: DateTime.utc(2030, 3, 2, 12, 30),
      location: '5 Baghdad St; floor 2',
    );
    expect(ics, contains('DTSTART:20300302T080000Z'));
    expect(ics, contains('DTEND:20300302T123000Z'));
    expect(ics, contains('SUMMARY:Implant case\\, Heliopolis'));
    expect(ics, contains('LOCATION:5 Baghdad St\\; floor 2'));
    expect(ics, contains('BEGIN:VALARM'));
    expect(ics.split('\r\n').first, 'BEGIN:VCALENDAR');
  });
}
