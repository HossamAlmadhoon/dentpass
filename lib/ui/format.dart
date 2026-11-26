import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

String _lang(BuildContext context) => Localizations.localeOf(context).languageCode;

String money(BuildContext context, int amount) => NumberFormat.decimalPattern(_lang(context)).format(amount);

String dayOfWeek(BuildContext context, DateTime d) => DateFormat.E(_lang(context)).format(d);
String dayOfMonth(BuildContext context, DateTime d) => DateFormat.d(_lang(context)).format(d);
String monthShort(BuildContext context, DateTime d) => DateFormat.MMM(_lang(context)).format(d);
String fullDate(BuildContext context, DateTime d) => DateFormat.yMMMEd(_lang(context)).format(d);
String time(BuildContext context, DateTime d) => DateFormat.Hm(_lang(context)).format(d);

/// "Sat, 28 Nov, 10:00–14:00", or both dates when a slot runs over several days.
String whenText(BuildContext context, DateTime start, DateTime end) {
  final lang = _lang(context);
  final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
  final day = DateFormat.MMMEd(lang);
  final comma = lang == 'ar' ? '،' : ',';
  if (sameDay) return '${day.format(start)}$comma ${time(context, start)}–${time(context, end)}';
  return '${day.format(start)} ${time(context, start)} – ${day.format(end)} ${time(context, end)}';
}

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
