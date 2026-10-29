import 'beacon_config.dart';

/// Evita abrir el mismo lugar dos veces por un pico o un corte breve de señal.
///
/// Hacen falta [BeaconConfig.confirmReadings] lecturas dentro del radio,
/// en [BeaconConfig.confirmWindow], para abrir. Una lectura fuera no las borra.
enum ExhibitionChoice { ignore, same, show }

class BeaconSession {
  final Set<String> open = {};
  final Map<String, DateTime> _lastSeen = {};
  final Map<String, DateTime> _awaySince = {};
  final Map<String, List<DateTime>> _hits = {};
  final Map<String, List<int>> _samples = {};
  final Map<String, int> _level = {};
  DateTime? _lastOpen;
  String? exhibitionKey;
  String? _rival;
  DateTime? _rivalSince;
  DateTime? _rivalHeard;

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
    int exitRssi = BeaconConfig.rssiExit,
    DateTime? now,
    int required = BeaconConfig.confirmReadings,
    Duration window = BeaconConfig.confirmWindow,
    Duration cooldown = BeaconConfig.openCooldown,
  }) {
    final moment = now ?? DateTime.now();
    if (open.contains(key)) return false;

    final hits = _hits.putIfAbsent(key, () => <DateTime>[]);
    hits.removeWhere((time) => moment.difference(time) > window);
    // La primera tiene que entrar al radio. La siguiente vale si no se salió.
    final counts = hits.isEmpty ? rssi >= enter : rssi >= exitRssi;
    if (!counts) return false;
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

  /// Promedio de las últimas [BeaconConfig.smoothCount] lecturas de esta clave.
  int smooth(String key, int rssi) {
    final bucket = _samples.putIfAbsent(key, () => <int>[]);
    bucket.add(rssi);
    final extra = bucket.length - BeaconConfig.smoothCount;
    if (extra > 0) bucket.removeRange(0, extra);
    final sum = bucket.fold<int>(0, (total, value) => total + value);
    return (sum / bucket.length).round();
  }

  /// Decide si esta clave debe mostrarse. [rssi] dice si está dentro de la zona.
  /// Si otra cripta también está en su zona, se cambia a los 3 segundos.
  /// No cambia la exhibición actual: eso ocurre en [commitExhibition].
  ExhibitionChoice consider(
    String key,
    int rssi,
    DateTime now, {
    required bool justOpened,
    int? level,
  }) {
    final strength = level ?? rssi;
    _level[key] = strength;
    if (exhibitionKey == key) {
      if (rssi >= BeaconConfig.rssiExit) return ExhibitionChoice.same;
      return ExhibitionChoice.ignore;
    }
    if (rssi < BeaconConfig.rssiEnter) {
      _dropRival(key);
      return ExhibitionChoice.ignore;
    }
    if (exhibitionKey == null) {
      return justOpened ? ExhibitionChoice.show : ExhibitionChoice.ignore;
    }
    final previous = _rival == key ? _rivalHeard : null;
    if (_rival != key ||
        previous == null ||
        now.difference(previous) > BeaconConfig.switchHold) {
      _rival = key;
      _rivalSince = now;
      _rivalHeard = now;
      return ExhibitionChoice.ignore;
    }
    _rivalHeard = now;
    final since = _rivalSince;
    if (since == null || now.difference(since) < BeaconConfig.switchHold) {
      return ExhibitionChoice.ignore;
    }
    return ExhibitionChoice.show;
  }

  void commitExhibition(String key) {
    exhibitionKey = key;
    _rival = null;
    _rivalSince = null;
    _rivalHeard = null;
  }

  /// Suelta solo las claves de la exhibición que se dejó de oír.
  void dropExhibition(Iterable<String> keys) {
    for (final key in keys) {
      release(key);
      _level.remove(key);
    }
    exhibitionKey = null;
    _rival = null;
    _rivalSince = null;
    _rivalHeard = null;
  }

  void _dropRival(String key) {
    if (_rival != key) return;
    _rival = null;
    _rivalSince = null;
    _rivalHeard = null;
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
    _samples.clear();
    _level.clear();
    _lastOpen = null;
    exhibitionKey = null;
    _rival = null;
    _rivalSince = null;
    _rivalHeard = null;
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
      _addKey(keys, value);
      final mac = macOf(value);
      if (mac != null) _addKey(keys, mac);
    }
    return keys;
  }

  /// Lectura útil del beacon. Un decimal cuenta. 0 y 127 no son señal.
  static int? readRssi(Object? value) {
    final int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.round();
    } else {
      final text = '${value ?? ''}'.trim();
      parsed = text.isEmpty ? null : int.tryParse(text) ?? double.tryParse(text)?.round();
    }
    if (parsed == null || parsed >= 0) return null;
    return parsed;
  }

  /// MAC canónica `AA:BB:CC:DD:EE:FF`, venga con dos puntos o pegada.
  static String? macOf(String value) {
    final hex = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (hex.length != 12) return null;
    final pairs = <String>[];
    for (var index = 0; index < 12; index += 2) {
      pairs.add(hex.substring(index, index + 2).toUpperCase());
    }
    return pairs.join(':');
  }

  static void _addKey(List<String> keys, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || keys.contains(trimmed)) return;
    keys.add(trimmed);
  }
}
