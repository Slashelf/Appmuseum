import 'package:app_guia_v1/core/beacons/beacon_config.dart';
import 'package:app_guia_v1/core/beacons/beacon_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool confirm(BeaconSession session, String key, int rssi, DateTime start) {
    var opened = false;
    for (var index = 0; index < BeaconConfig.confirmReadings; index++) {
      final moment = start.add(Duration(seconds: index));
      session.reading(keys: [key], rssi: rssi, now: moment);
      opened = session.tryOpen(key, rssi, now: moment);
    }
    return opened;
  }

  test('a close beacon opens once until the signal is really gone', () {
    final session = BeaconSession();
    final start = DateTime(2026, 10, 20, 12);
    const mac = 'D5:E0:59:B6:6F:C8';

    expect(confirm(session, mac, -55, start), isTrue);
    expect(session.tryOpen(mac, -50, now: start.add(const Duration(seconds: 3))), isFalse);

    session.reading(
      keys: const [mac],
      rssi: -90,
      now: start.add(const Duration(seconds: 5)),
    );
    expect(session.tryOpen(mac, -55, now: start.add(const Duration(seconds: 5))), isFalse);

    session.reading(
      keys: const [mac],
      rssi: -90,
      now: start.add(const Duration(seconds: 14)),
    );
    expect(confirm(session, mac, -55, start.add(const Duration(seconds: 14))), isTrue);
  });

  test('a brief gap does not open the same beacon again', () {
    final session = BeaconSession();
    final start = DateTime(2026, 10, 20, 12);
    expect(confirm(session, 'AA', -40, start), isTrue);

    session.reading(
      keys: const ['AA'],
      rssi: -40,
      now: start.add(const Duration(seconds: 3)),
    );
    expect(session.tryOpen('AA', -40, now: start.add(const Duration(seconds: 3))), isFalse);
  });

  test('a signal near one metre opens and a weaker one stays closed', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    expect(BeaconConfig.rssiEnter, -56);
    expect(BeaconConfig.rssiExit, -80);
    expect(BeaconConfig.confirmReadings, 1);
    expect(BeaconConfig.openCooldown, Duration.zero);

    var opened = false;
    for (var index = 0; index < 3; index++) {
      opened = session.tryOpen('FAR', -68, now: now.add(Duration(seconds: index)));
    }
    expect(opened, isFalse);

    expect(confirm(session, 'NEAR', -56, now), isTrue);
    for (var second = 3; second <= 20; second += 2) {
      session.reading(
        keys: const ['NEAR'],
        rssi: -80,
        now: now.add(Duration(seconds: second)),
      );
    }
    expect(session.open, contains('NEAR'));

    final away = now.add(const Duration(seconds: 22));
    session.reading(keys: const ['NEAR'], rssi: -81, now: away);
    session.reading(keys: const ['NEAR'], rssi: -81, now: away.add(const Duration(seconds: 8)));
    expect(session.open, isNot(contains('NEAR')));
  });

  test('one close reading opens immediately and a weak one does not', () {
    final session = BeaconSession();
    final start = DateTime(2026, 10, 20, 12);
    expect(session.tryOpen('AA', -50, now: start), isTrue);
    expect(session.tryOpen('WEAK', -70, now: start), isFalse);
  });

  test('a different beacon can open at once and the same one stays quiet', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    expect(confirm(session, 'AA', -50, now), isTrue);
    expect(session.tryOpen('BB', -50, now: now), isTrue);
    expect(session.tryOpen('AA', -50, now: now.add(const Duration(seconds: 1))), isFalse);
  });
}
