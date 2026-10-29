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

    expect(confirm(session, mac, -40, start), isTrue);
    expect(session.tryOpen(mac, -50, now: start.add(const Duration(seconds: 3))), isFalse);

    session.reading(
      keys: const [mac],
      rssi: -70,
      now: start.add(const Duration(seconds: 5)),
    );
    expect(session.tryOpen(mac, -56, now: start.add(const Duration(seconds: 5))), isFalse);

    session.reading(
      keys: const [mac],
      rssi: -70,
      now: start.add(const Duration(seconds: 14)),
    );
    expect(session.open, contains(mac));
    expect(session.tryOpen(mac, -56, now: start.add(const Duration(seconds: 14))), isFalse);

    final gone = start.add(const Duration(seconds: 20));
    session.reading(keys: const [mac], rssi: -90, now: gone);
    expect(session.open, contains(mac));
    session.reading(keys: const [mac], rssi: -90, now: gone.add(const Duration(seconds: 8)));
    expect(session.open, isNot(contains(mac)));
    expect(confirm(session, mac, -40, gone.add(const Duration(seconds: 9))), isTrue);
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

  test('one reading at the old threshold opens and a weaker one stays closed', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    expect(BeaconConfig.rssiNear, -40);
    expect(BeaconConfig.rssiEnter, -40);
    expect(BeaconConfig.rssiExit, -80);
    expect(BeaconConfig.confirmReadings, 1);
    expect(BeaconConfig.openCooldown, Duration.zero);

    expect(session.tryOpen('NEAR', -40, now: now), isTrue);
    expect(session.tryOpen('EDGE', -40, now: now), isTrue);
    expect(session.tryOpen('OUT', -90, now: now), isFalse);
    expect(
      session.tryOpen('OUT', -90, now: now.add(const Duration(seconds: 1))),
      isFalse,
    );

    for (var second = 3; second <= 20; second += 2) {
      session.reading(
        keys: const ['NEAR'],
        rssi: -70,
        now: now.add(Duration(seconds: second)),
      );
    }
    expect(session.open, contains('NEAR'));

    final away = now.add(const Duration(seconds: 22));
    session.reading(keys: const ['NEAR'], rssi: -75, now: away);
    session.reading(keys: const ['NEAR'], rssi: -75, now: away.add(const Duration(seconds: 8)));
    expect(session.open, contains('NEAR'));

    session.reading(keys: const ['NEAR'], rssi: -90, now: away.add(const Duration(seconds: 9)));
    expect(session.open, contains('NEAR'));
    session.reading(
      keys: const ['NEAR'],
      rssi: -90,
      now: away.add(const Duration(seconds: 17)),
    );
    expect(session.open, isNot(contains('NEAR')));
  });

  test('a reading weaker than the zone does not open', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    expect(session.tryOpen('AA', -40, now: now), isTrue);
    expect(session.tryOpen('WEAK', -56, now: now), isFalse);
    expect(
      session.tryOpen('WEAK', -56, now: now.add(const Duration(seconds: 1))),
      isFalse,
    );
    expect(session.open, isNot(contains('WEAK')));
  });

  test('one close reading opens and a weak one does not', () {
    final session = BeaconSession();
    final start = DateTime(2026, 10, 20, 12);
    expect(session.tryOpen('AA', -40, now: start), isTrue);
    expect(session.tryOpen('WEAK', -56, now: start), isFalse);
    expect(session.tryOpen('WEAK', -56, now: start.add(const Duration(seconds: 1))), isFalse);
  });

  test('a stronger beacon waits three seconds and the same one stays quiet', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    expect(confirm(session, 'AA', -40, now), isTrue);
    final openedAt = now.add(const Duration(seconds: 1));
    expect(
      session.consider('AA', -40, openedAt, justOpened: true),
      ExhibitionChoice.show,
    );
    session.commitExhibition('AA');

    final rivalAt = now.add(const Duration(seconds: 2));
    expect(
      session.consider('BB', -40, rivalAt, justOpened: true),
      ExhibitionChoice.ignore,
    );
    expect(
      session.consider('AA', -40, rivalAt.add(const Duration(seconds: 1)), justOpened: false),
      ExhibitionChoice.same,
    );
    expect(
      session.consider('BB', -40, rivalAt.add(const Duration(seconds: 2)), justOpened: false),
      ExhibitionChoice.ignore,
    );
    expect(
      session.consider('BB', -40, rivalAt.add(const Duration(seconds: 3)), justOpened: false),
      ExhibitionChoice.show,
    );

    expect(session.tryOpen('AA', -40, now: now.add(const Duration(seconds: 6))), isFalse);
    final weakerAt = now.add(const Duration(seconds: 8));
    expect(
      session.consider('CC', -40, weakerAt, justOpened: true),
      ExhibitionChoice.ignore,
    );
    expect(
      session.consider('AA', -40, weakerAt.add(const Duration(seconds: 1)), justOpened: false),
      ExhibitionChoice.same,
    );
    expect(
      session.consider('CC', -40, weakerAt.add(const Duration(seconds: 3)), justOpened: false),
      ExhibitionChoice.show,
    );
  });

  test('a weak reading does not block the next one inside the zone', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    expect(session.tryOpen('AA', -90, now: now), isFalse);
    expect(session.tryOpen('AA', -40, now: now.add(const Duration(seconds: 1))), isTrue);
  });

  test('a decimal rssi counts and a bare mac matches the stored one', () {
    expect(BeaconIdentity.readRssi(-65.4), -65);
    expect(BeaconIdentity.readRssi('-70.0'), -70);
    expect(BeaconIdentity.readRssi(0), isNull);
    expect(BeaconIdentity.readRssi(127), isNull);
    expect(BeaconIdentity.macOf('d5e059b66fc8'), 'D5:E0:59:B6:6F:C8');
    expect(
      BeaconIdentity.keysFrom({
        'id': 'd5e059b66fc8',
        'rssi': -86.2,
      }),
      contains('D5:E0:59:B6:6F:C8'),
    );
  });

  test('the smoothed signal uses the last four readings', () {
    final session = BeaconSession();
    expect(session.smooth('AA', -40), -40);
    expect(session.smooth('AA', -80), -60);
    expect(session.smooth('AA', -80), -67);
    expect(session.smooth('AA', -80), -70);
    expect(session.smooth('AA', -80), -80);
  });

  test('the open exhibition stays while it is still heard above the exit', () {
    final session = BeaconSession();
    final now = DateTime(2026, 10, 20, 12);
    session.commitExhibition('AA');
    expect(session.consider('AA', -56, now, justOpened: false), ExhibitionChoice.same);
    expect(session.consider('AA', -80, now, justOpened: false), ExhibitionChoice.same);
    expect(session.consider('AA', -90, now, justOpened: false), ExhibitionChoice.ignore);
  });
}
