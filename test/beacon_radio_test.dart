import 'package:app_guia_v1/core/beacons/beacon_radio_watch.dart';
import 'package:app_guia_v1/core/beacons/beacon_session.dart';
import 'package:app_guia_v1/core/locale/locale_controller.dart';
import 'package:app_guia_v1/data/content_repository.dart';
import 'package:app_guia_v1/models/object_carousel_model.dart';
import 'package:app_guia_v1/models/object_model.dart';
import 'package:app_guia_v1/models/recommended_model.dart';
import 'package:app_guia_v1/repositories/data_repository.dart';
import 'package:app_guia_v1/screens/app_localizations.dart';
import 'package:app_guia_v1/screens/beacon_scan_services.dart';
import 'package:app_guia_v1/screens/home_screen.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BeaconServiceFlutter().debugSkipPlugin = true;
  test('a healthy radio is left running when the mode changes', () {
    final watch = BeaconRadioWatch()
      ..enabled = true
      ..scanning = true
      ..subscriptionAlive = true;
    expect(watch.onModeChanged(), isFalse);
    expect(watch.recoveries, 0);
    expect(watch.scanning, isTrue);
  });

  test('a dead radio is asked to start again and the exhibition stays', () async {
    final service = BeaconServiceFlutter();
    service.session.markOpen('exhibicion-viva');
    service.debugPrepare(scanEnabled: true, scanningNow: true, alive: false);
    final openBefore = service.session.open.length;
    service.debugStreamEnded();
    expect(service.watch.recoveries, 1);
    expect(service.scanning, isFalse);
    expect(service.session.open.contains('exhibicion-viva'), isTrue);
    expect(service.session.open.length, openBefore);

    service.debugPrepare(scanEnabled: true, scanningNow: false, alive: false);
    await service.recoverScan();
    expect(service.watch.recoveries, 1);
    expect(service.session.open.contains('exhibicion-viva'), isTrue);
  });

  test('a stopped beacon is not revived by a dead stream', () {
    final service = BeaconServiceFlutter();
    service.debugPrepare(scanEnabled: false, scanningNow: false, alive: false);
    service.debugStreamEnded();
    expect(service.watch.recoveries, 0);
  });

  test('a failed start keeps scanning enabled unless permission was denied', () {
    fakeAsync((async) {
      final service = BeaconServiceFlutter();
      service.debugSkipPlugin = true;
      service.debugPrepare(scanEnabled: true, scanningNow: false, alive: false);
      service.debugStartFailed(permissionsDenied: false);
      expect(service.enabled, isTrue);
      expect(service.debugLastNotice, isNull);
      expect(service.debugRetries, 1);
      service.debugStartFailed(permissionsDenied: false);
      service.debugStartFailed(permissionsDenied: false);
      service.debugStartFailed(permissionsDenied: false);
      expect(service.debugRetries, 4);
      expect(service.enabled, isTrue);
      async.elapse(const Duration(seconds: 4));

      service.debugPrepare(scanEnabled: true, scanningNow: false, alive: false);
      service.debugStartFailed(permissionsDenied: true);
      expect(service.enabled, isFalse);
      expect(service.debugLastNotice, contains('Permisos'));
    });
  });

  test('fifteen seconds without the beacon clears the exhibition only', () {
    fakeAsync((async) {
      final service = BeaconServiceFlutter();
      service.debugSkipPlugin = true;
      final seen = <ObjectModel?>[];
      service.addPlaceListener(seen.add);
      service.debugShow(
        _place('sf'),
        keys: const ['D5:E0:59:B6:6F:C8'],
      );
      service.session.markOpen('otro-beacon');
      expect(seen.single?.id, 'sf');

      async.elapse(const Duration(seconds: 14));
      expect(seen.single?.id, 'sf');

      async.elapse(const Duration(seconds: 1));
      expect(seen.last, isNull);
      expect(service.session.open.contains('otro-beacon'), isTrue);
      expect(service.session.open.contains('sf'), isFalse);
    });
  });

  test('a scan that does not start is not left running', () {
    fakeAsync((async) {
      final service = BeaconServiceFlutter();
      service.debugSkipPlugin = true;
      service.debugPrepare(scanEnabled: true, scanningNow: true, alive: true);
      service.debugApplyNativeStart(false);
      async.flushMicrotasks();
      expect(service.scanning, isFalse);
      expect(service.enabled, isTrue);
      expect(service.debugRetries, 1);
      async.elapse(const Duration(seconds: 4));
    });
  });

  test('a reading inside the radius opens and a miss does not stick', () async {
    final service = BeaconServiceFlutter();
    service.debugSkipPlugin = true;
    service.session.clear();
    service.debugPrepare(scanEnabled: true, scanningNow: false, alive: false);
    final seen = <ObjectModel?>[];
    void listener(ObjectModel? place) => seen.add(place);
    service.addPlaceListener(listener);
    final start = DateTime(2026, 10, 26, 12);
    final device = <String, dynamic>{
      'id': 'd5e059b66fc8',
      'rssi': -35.4,
    };
    var calls = 0;

    Future<ObjectModel?> lookup(Map<String, dynamic> raw) async {
      calls += 1;
      expect(BeaconIdentity.keysFrom(raw), contains('D5:E0:59:B6:6F:C8'));
      return calls == 1 ? null : _place('D5:E0:59:B6:6F:C8');
    }

    await service.debugIngest(device, now: start, lookup: lookup);
    expect(calls, 1);
    expect(seen, isEmpty);
    expect(service.session.open, isEmpty);

    await service.debugIngest(
      {'id': 'AA', 'rssi': 127},
      now: start.add(const Duration(seconds: 2)),
      lookup: lookup,
    );
    expect(calls, 1);

    await service.debugIngest(
      device,
      now: start.add(const Duration(seconds: 3)),
      lookup: lookup,
    );
    expect(calls, 2);
    expect(seen.single?.id, 'D5:E0:59:B6:6F:C8');
    service.removePlaceListener(listener);
    service.session.clear();
    service.debugPrepare(scanEnabled: false, scanningNow: false, alive: false);
  });

  test('a beacon that is still heard does not clear after fifteen seconds', () {
    fakeAsync((async) {
      final service = BeaconServiceFlutter();
      service.debugSkipPlugin = true;
      final seen = <ObjectModel?>[];
      service.addPlaceListener(seen.add);
      service.debugShow(_place('sf'), keys: const ['AA']);
      async.elapse(const Duration(seconds: 10));
      service.debugHearCurrent(-40);
      async.elapse(const Duration(seconds: 14));
      expect(seen.last?.id, 'sf');
      async.elapse(const Duration(seconds: 1));
      expect(seen.last, isNull);
    });
  });

  testWidgets('closing home leaves the beacon session running', (tester) async {
    SharedPreferences.setMockInitialValues({});
    DataRepository.bind(_EmptyContent());
    final service = BeaconServiceFlutter();
    service.debugSkipPlugin = true;
    service.debugPrepare(scanEnabled: true, scanningNow: true, alive: true);
    service.session.markOpen('sigue');

    await tester.pumpWidget(_home(locationOn: true));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('location-off')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(service.session.open.contains('sigue'), isTrue);
    expect(service.enabled, isTrue);
  });

  testWidgets('a switched-off location shows a button to turn it on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    DataRepository.bind(_EmptyContent());
    var opened = 0;
    await tester.pumpWidget(_home(
      locationOn: false,
      onOpen: () async => opened += 1,
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('location-off')), findsOneWidget);
    expect(find.text('La ubicación está apagada. Enciéndela para detectar las exhibiciones.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('location-on')));
    await tester.pump();
    expect(opened, 1);
    expect(AppLocalizations(const Locale('en')).get('locationTurnOn'), 'Turn on location');
    expect(AppLocalizations(const Locale('de')).get('locationOff'), contains('Standort'));
  });
}

class _EmptyContent implements ContentRepository {
  @override
  Future<ObjectCarousel?> getCarousel() async => null;

  @override
  Future<ObjectModel?> findByCode(String code) async => null;

  @override
  Future<List<ObjectModel>> getPlaces() async => const <ObjectModel>[];

  @override
  Future<List<RecommendedModel>> getRecommended() async =>
      const <RecommendedModel>[];

  @override
  Future<void> savePendingComment(PendingComment comment) async {}
}

ObjectModel _place(String id) {
  return ObjectModel(
    id: id,
    name: id,
    name2: id,
    description: 'texto',
    cryptDescription: 'cripta',
    imageUrl: 'a.png',
    imageUrl2: 'b.png',
  );
}

Widget _home({required bool locationOn, Future<void> Function()? onOpen}) {
  return ChangeNotifierProvider(
    create: (_) => LocaleController(),
    child: MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
      home: MainScreen(
        showTutorial: false,
        locationServicesOn: () async => locationOn,
        openLocationSettings: onOpen ?? () async {},
      ),
    ),
  );
}
