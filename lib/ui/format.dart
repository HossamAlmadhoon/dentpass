import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:dentpass/l10n/app_localizations.dart';

String _lang(BuildContext context) => Localizations.localeOf(context).languageCode;

const _easternDigits = '٠١٢٣٤٥٦٧٨٩';

/// One set of digits everywhere: 0–9, as on phone numbers, prices and InstaPay.
String latinDigits(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final i = _easternDigits.indexOf(String.fromCharCode(r));
    out.write(i >= 0 ? '$i' : String.fromCharCode(r));
  }
  return out.toString().replaceAll('٬', ',').replaceAll('٫', '.');
}

String money(BuildContext context, int amount) => NumberFormat.decimalPattern('en').format(amount);

String dayOfWeek(BuildContext context, DateTime d) => DateFormat.E(_lang(context)).format(d);
String dayOfMonth(BuildContext context, DateTime d) => latinDigits(DateFormat.d(_lang(context)).format(d));
String monthShort(BuildContext context, DateTime d) => DateFormat.MMM(_lang(context)).format(d);
String fullDate(BuildContext context, DateTime d) => latinDigits(DateFormat.yMMMEd(_lang(context)).format(d));

/// "10 AM", "2:30 PM" / "10 ص", "2:30 م".
String time(BuildContext context, DateTime d) {
  final ar = _lang(context) == 'ar';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  final half = d.hour < 12 ? (ar ? 'ص' : 'AM') : (ar ? 'م' : 'PM');
  return '$h$m $half';
}

int _daysFromToday(DateTime d) {
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// "Today", "Tomorrow", or the short weekday.
String dayLabel(BuildContext context, DateTime d) {
  final t = AppLocalizations.of(context);
  return switch (_daysFromToday(d)) { 0 => t.today, 1 => t.tomorrow, _ => dayOfWeek(context, d) };
}

/// "Today", "Tomorrow", or "Sat 28 Nov".
String dayText(BuildContext context, DateTime d) {
  final days = _daysFromToday(d);
  if (days == 0 || days == 1) return dayLabel(context, d);
  return latinDigits(DateFormat.MMMEd(_lang(context)).format(d));
}

/// "Sat 28 Nov, 10 AM – 2 PM" ("Today, …" when it is today), or both dates when a slot runs over several days.
String whenText(BuildContext context, DateTime start, DateTime end) {
  final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
  final comma = _lang(context) == 'ar' ? '،' : ',';
  if (sameDay) return '${dayText(context, start)}$comma ${time(context, start)} – ${time(context, end)}';
  return '${dayText(context, start)} ${time(context, start)} – ${dayText(context, end)} ${time(context, end)}';
}

/// "10 AM – 2 PM".
String hoursText(BuildContext context, DateTime start, DateTime end) => '${time(context, start)} – ${time(context, end)}';

String initials(String name) {
  final parts = name
      .replaceAll(RegExp(r'^(Dr\.?|د\.?)\s*', caseSensitive: false), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final last = parts.length > 1 ? parts.last.characters.first : '';
  return (first + last).toUpperCase();
}
