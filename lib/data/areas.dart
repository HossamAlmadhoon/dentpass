import 'package:flutter/widgets.dart';

/// Areas are stored as keys; names are shown in the user's language.
/// The pilot covers Cairo and Giza. Add more here as you grow.
const Map<String, List<String>> _areas = {
  'nasr_city': ['Nasr City', 'مدينة نصر'],
  'heliopolis': ['Heliopolis', 'مصر الجديدة'],
  'new_cairo': ['New Cairo', 'القاهرة الجديدة'],
  'maadi': ['Maadi', 'المعادي'],
  'downtown': ['Downtown', 'وسط البلد'],
  'zamalek': ['Zamalek', 'الزمالك'],
  'shubra': ['Shubra', 'شبرا'],
  'dokki': ['Dokki', 'الدقي'],
  'mohandessin': ['Mohandessin', 'المهندسين'],
  'haram': ['Haram', 'الهرم'],
  'october': ['6th of October', 'السادس من أكتوبر'],
  'zayed': ['Sheikh Zayed', 'الشيخ زايد'],
};

List<String> get areaKeys => _areas.keys.toList();

String areaName(BuildContext context, String? key) {
  if (key == null || key.isEmpty) return '';
  final names = _areas[key];
  if (names == null) return key;
  return Localizations.localeOf(context).languageCode == 'ar' ? names[1] : names[0];
}
