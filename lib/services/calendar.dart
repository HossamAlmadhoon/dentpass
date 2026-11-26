import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

String _stamp(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _escape(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

/// A calendar file (.ics) that phone calendars can import.
String buildIcs({required String id, required String title, required DateTime start, required DateTime end, String location = '', String details = ''}) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//DentPass//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    'UID:$id@dentpass.app',
    'DTSTAMP:${_stamp(DateTime.now())}',
    'DTSTART:${_stamp(start)}',
    'DTEND:${_stamp(end)}',
    'SUMMARY:${_escape(title)}',
    if (location.isNotEmpty) 'LOCATION:${_escape(location)}',
    if (details.isNotEmpty) 'DESCRIPTION:${_escape(details)}',
    'BEGIN:VALARM',
    'TRIGGER:-PT2H',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_escape(title)}',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}

/// Opens the phone's own calendar (iPhone Calendar) with the event ready to add.
Future<bool> openPhoneCalendar(String ics) {
  if (!kIsWeb) return Future.value(false);
  return launchUrl(Uri.parse('data:text/calendar;charset=utf-8,${Uri.encodeComponent(ics)}'));
}

/// Opens Google Calendar with the event filled in.
Future<bool> openGoogleCalendar({required String title, required DateTime start, required DateTime end, String location = '', String details = ''}) {
  final uri = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_stamp(start)}/${_stamp(end)}',
    if (location.isNotEmpty) 'location': location,
    if (details.isNotEmpty) 'details': details,
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
