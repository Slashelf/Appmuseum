import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idioma de la guía. Se guarda entre pantallas y al cerrar la app.
class LocaleController extends ChangeNotifier {
  static const storageKey = 'app_locale';
  static const supported = ['es', 'en', 'de'];

  Locale _locale = const Locale('es');

  Locale get locale => _locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(storageKey);
    if (code != null && supported.contains(code)) {
      _locale = Locale(code);
    }
  }

  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode;
    if (!supported.contains(code) || code == _locale.languageCode) return;
    _locale = Locale(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, code);
  }
}
