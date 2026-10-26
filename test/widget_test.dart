import 'package:app_guia_v1/screens/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_guia_v1/core/locale/locale_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('es, en and de expose the same text keys', () {
    expect(AppLocalizations.catalogProblems(), isEmpty);
    final spanish = AppLocalizations(const Locale('es'));
    final english = AppLocalizations(const Locale('en'));
    final german = AppLocalizations(const Locale('de'));
    for (final key in [
      'gallery',
      'beaconActivated',
      'objectNotFound',
      'seeMore2',
      'beaconTutorial',
    ]) {
      expect(english.get(key), isNot(spanish.get(key)));
      expect(german.get(key), isNot(key));
      expect(english.get(key), isNot(key));
    }
  });

  test('the chosen language is kept', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = LocaleController();
    await controller.load();
    expect(controller.locale.languageCode, 'es');
    await controller.setLocale(const Locale('de'));
    final again = LocaleController();
    await again.load();
    expect(again.locale.languageCode, 'de');
  });
}
