import 'package:app_guia_v1/core/beacons/beacon_radio_watch.dart';
import 'package:app_guia_v1/screens/beacon_scan_services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
