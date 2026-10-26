import 'beacon_config.dart';

/// Evita abrir el mismo lugar dos veces por un pico o un corte breve de señal.
///
/// Hacen falta [BeaconConfig.confirmReadings] lecturas seguidas, iguales o
/// mejores que [BeaconConfig.rssiEnter], y debe haber pasado
/// [BeaconConfig.openCooldown] desde la apertura anterior.
class BeaconSession {
  final Set<String> open = {};
  final Map<String, DateTime> _lastSeen = {};
  final Map<String, DateTime> _awaySince = {};
  final Map<String, List<DateTime>> _hits = {};
  DateTime? _lastOpen;

  void reading({
    required List<String> keys,
    required int rssi,
    required DateTime now,
    int enter = BeaconConfig.rssiEnter,
    int exitRssi = BeaconConfig.rssiExit,
    Duration grace = BeaconConfig.signalGrace,
  }) {
    final stale = _lastSeen.entries
        .where((entry) => !keys.contains(entry.key))
        .where((entry) => now.difference(entry.value) >= grace)
        .map((entry) => entry.key)
        .toList();
    for (final key in stale) {
      open.remove(key);
      _lastSeen.remove(key);
      _awaySince.remove(key);
      _hits.remove(key);
    }

    for (final key in keys) {
      final previous = _lastSeen[key];
      if (previous != null && now.difference(previous) >= grace) {
        open.remove(key);
        _awaySince.remove(key);
      }
      _lastSeen[key] = now;

      if (rssi >= enter) {
        _awaySince.remove(key);
      } else if (rssi < exitRssi) {
        final since = _awaySince.putIfAbsent(key, () => now);
        if (now.difference(since) >= grace) {
          open.remove(key);
          _awaySince.remove(key);
        }
      } else {
        _awaySince.remove(key);
      }
    }
  }

  bool tryOpen(
    String key,
    int rssi, {
    int enter = BeaconConfig.rssiEnter,
    DateTime? now,
    int required = BeaconConfig.confirmReadings,
    Duration window = BeaconConfig.confirmWindow,
    Duration cooldown = BeaconConfig.openCooldown,
  }) {
    final moment = now ?? DateTime.now();
    if (rssi < enter) {
      _hits.remove(key);
      return false;
    }
    if (open.contains(key)) return false;

    final hits = _hits.putIfAbsent(key, () => <DateTime>[]);
    hits.removeWhere((time) => moment.difference(time) > window);
    hits.add(moment);
    if (hits.length < required) return false;
    if (_lastOpen != null && moment.difference(_lastOpen!) < cooldown) {
      return false;
    }

    hits.clear();
    open.add(key);
    _awaySince.remove(key);
    _lastOpen = moment;
    return true;
  }

  void markOpen(String key) {
    open.add(key);
    _awaySince.remove(key);
  }

  void release(String key) {
    open.remove(key);
    _awaySince.remove(key);
  }

  void clear() {
    open.clear();
    _lastSeen.clear();
    _awaySince.clear();
    _hits.clear();
    _lastOpen = null;
  }
}

/// Claves con las que ya se identifica un beacon, sin cambiar el UUID ni las MAC.
class BeaconIdentity {
  static List<String> keysFrom(Map<String, dynamic> device) {
    final raw = <String>[
      device['id']?.toString() ?? '',
      device['mac']?.toString() ?? '',
      device['address']?.toString() ?? '',
      device['name']?.toString() ?? '',
    ];
    final keys = <String>[];
    for (final value in raw) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || keys.contains(trimmed)) continue;
      keys.add(trimmed);
    }
    return keys;
  }
}
