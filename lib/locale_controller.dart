import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's language. Arabic by default; the choice is remembered on the device.
class LocaleController extends ValueNotifier<Locale> {
  LocaleController(super.value);

  static const _key = 'locale';

  static Future<LocaleController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LocaleController(Locale(prefs.getString(_key) ?? 'ar'));
  }

  Future<void> setLanguage(String code) async {
    value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }
}

/// Set once in main() before the app starts.
late LocaleController localeController;
