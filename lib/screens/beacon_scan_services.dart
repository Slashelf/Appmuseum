import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:beacons_flutter/beacons_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/beacons/beacon_config.dart';
import '../core/beacons/beacon_radio_watch.dart';
import '../core/beacons/beacon_session.dart';
import '../models/object_model.dart';
import '../repositories/data_repository.dart';

class BeaconServiceFlutter {
  static final BeaconServiceFlutter _instance = BeaconServiceFlutter._internal();
  factory BeaconServiceFlutter() => _instance;
  BeaconServiceFlutter._internal();

  final BeaconsFlutter _beaconsPlugin = BeaconsFlutter();
  final BeaconSession session = BeaconSession();
  final BeaconRadioWatch watch = BeaconRadioWatch();
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;

  bool scanning = false;
  bool enabled = false;
  bool _holding = false;

  /// Las pruebas no abren Bluetooth. `flutter test` a veces no define
  /// la constante de compilación, así que también se mira el proceso.
  @visibleForTesting
  bool debugSkipPlugin = false;
  int _listenGeneration = 0;
  int _lostBurst = 0;
  DateTime? _lostBurstAt;

  void Function(ObjectModel obj)? _onObjectFound;
  void Function(String message)? _onMessage;
  final List<void Function(ObjectModel place)> _placeListeners = [];
  final List<void Function(bool enabled)> _enabledListeners = [];
  List<String>? _iBeaconUUIDs;
  String _permissionDeniedMessage = 'Permisos denegados para escaneo BLE';

  /// Umbral de entrada. Apunta a cerca de un metro.
  int rssiThreshold = BeaconConfig.rssiEnter;

  /// Avisa el lugar al chat. No sustituye la apertura de la ficha.
  void addPlaceListener(void Function(ObjectModel place) listener) {
    if (_placeListeners.contains(listener)) return;
    _placeListeners.add(listener);
  }

  void removePlaceListener(void Function(ObjectModel place) listener) {
    _placeListeners.remove(listener);
  }

  /// El inicio refleja si el visitante dejó el escaneo encendido.
  void addEnabledListener(void Function(bool enabled) listener) {
    if (_enabledListeners.contains(listener)) return;
    _enabledListeners.add(listener);
  }

  void removeEnabledListener(void Function(bool enabled) listener) {
    _enabledListeners.remove(listener);
  }

  void bindFound(void Function(ObjectModel obj) handler) {
    _onObjectFound = handler;
  }

  /// Enciende el escaneo si estaba apagado. No cambia el aviso de la ficha.
  Future<void> ensureScan({
    required void Function(String message) onMessage,
    String? permissionDeniedMessage,
  }) {
    if (_radioUnderTest) return Future.value();
    if (scanning) return Future.value();
    return startScan(
      onObjectFound: _onObjectFound ?? (_) {},
      onMessage: onMessage,
      iBeaconUUIDs: const [BeaconConfig.uuid],
      permissionDeniedMessage: permissionDeniedMessage,
    );
  }

  void _setEnabled(bool value) {
    watch.enabled = value;
    if (enabled == value) return;
    enabled = value;
    for (final listener in List<void Function(bool)>.of(_enabledListeners)) {
      listener(value);
    }
  }

  Future<void> startScan({
    required void Function(ObjectModel obj) onObjectFound,
    required void Function(String message) onMessage,
    List<String>? iBeaconUUIDs,
    String? permissionDeniedMessage,
  }) async {
    if (scanning) return;
    _holding = false;
    _onObjectFound = onObjectFound;
    _onMessage = onMessage;
    _iBeaconUUIDs = iBeaconUUIDs;
    if (permissionDeniedMessage != null && permissionDeniedMessage.isNotEmpty) {
      _permissionDeniedMessage = permissionDeniedMessage;
    }
    _setEnabled(true);
    await _startPlugin();
  }

  Future<void> _startPlugin() async {
    await _requestBlePermissions();

    try {
      final hasPermissions = await _beaconsPlugin.checkPermissions();
      if (!hasPermissions) {
        final granted = await _beaconsPlugin.requestPermissions();
        if (!granted) {
          scanning = false;
          watch.notePaused();
          _setEnabled(false);
          _onMessage?.call(_permissionDeniedMessage);
          return;
        }
      }

      await _scanSubscription?.cancel();
      final generation = ++_listenGeneration;
      _scanSubscription = _beaconsPlugin.scanResults.listen(
        _onDevice,
        onError: (Object error) {
          debugPrint('Beacon: $error');
          _onScanLost(generation);
        },
        onDone: () => _onScanLost(generation),
      );

      scanning = true;
      watch.noteStarted();
      await _beaconsPlugin.startScan(
        iBeaconUUIDs: _iBeaconUUIDs ??
            (Platform.isIOS ? [BeaconConfig.uuid] : <String>[]),
      );
    } catch (error) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      scanning = false;
      watch.notePaused();
      _setEnabled(false);
      _onMessage?.call(_permissionDeniedMessage);
      debugPrint('Beacon: $error');
    }
  }

  /// Pide los permisos de Bluetooth. La decisión final sigue siendo la del
  /// plugin, que es la que ya abre los lugares.
  Future<void> _requestBlePermissions() async {
    try {
      final permissions = Platform.isIOS
          ? <Permission>[Permission.bluetooth, Permission.locationWhenInUse]
          : <Permission>[
              Permission.bluetoothScan,
              Permission.bluetoothConnect,
              Permission.locationWhenInUse,
            ];
      await permissions.request();
    } catch (error) {
      debugPrint('Beacon: $error');
    }
  }

  Future<void> _onDevice(Map<String, dynamic> device) async {
    final rssiValue = device['rssi'];
    final rssi = rssiValue is int
        ? rssiValue
        : int.tryParse('${rssiValue ?? ''}') ?? -100;
    final keys = BeaconIdentity.keysFrom(device);
    if (keys.isEmpty) return;

    final now = DateTime.now();
    session.reading(keys: keys, rssi: rssi, now: now, enter: rssiThreshold);

    final fresh = <String>[];
    for (final key in keys) {
      if (session.tryOpen(key, rssi, enter: rssiThreshold)) fresh.add(key);
    }
    if (fresh.isEmpty) return;

    final place = await DataRepository.findByBeacon(device);
    if (place == null) {
      for (final key in fresh) {
        session.release(key);
      }
      return;
    }
    final alreadyOpen = session.open.contains(place.id) && !fresh.contains(place.id);
    session.markOpen(place.id);
    for (final listener in List<void Function(ObjectModel)>.of(_placeListeners)) {
      listener(place);
    }
    if (alreadyOpen) return;
    _onObjectFound?.call(place);
  }

  Future<void> pauseScan() async {
    if (!enabled) return;
    _holding = true;
    await _retireListen();
    try {
      await _beaconsPlugin.stopScan();
    } catch (error) {
      debugPrint('Beacon: $error');
    }
    scanning = false;
    watch.notePaused();
  }

  Future<void> resumeScan() async {
    _holding = false;
    if (!enabled || scanning) return;
    await _startPlugin();
  }

  /// Si el radio se cayó, lo vuelve a pedir. Un escaneo sano sigue igual.
  /// No vacía la sesión ni la exhibición.
  Future<void> recoverScan() {
    watch.enabled = enabled;
    if (_scanSubscription != null) {
      watch.scanning = scanning;
      watch.subscriptionAlive = true;
    } else if (scanning) {
      watch.scanning = true;
      watch.subscriptionAlive = false;
    } else {
      watch.scanning = false;
      watch.subscriptionAlive = false;
    }
    final restart = watch.onModeChanged();
    if (!restart) return Future.value();
    scanning = false;
    if (_radioUnderTest) return Future.value();
    return _startPlugin();
  }

  bool get _radioUnderTest {
    if (debugSkipPlugin || const bool.fromEnvironment('FLUTTER_TEST')) return true;
    return Platform.environment['FLUTTER_TEST'] == 'true';
  }

  /// El flujo terminó solo. Reanuda si el visitante no apagó el beacon.
  Future<void> _retireListen() async {
    final subscription = _scanSubscription;
    _listenGeneration++;
    _scanSubscription = null;
    await subscription?.cancel();
  }

  void _onScanLost(int generation) {
    if (generation != _listenGeneration) return;
    _listenGeneration++;
    _scanSubscription = null;
    scanning = false;
    if (_holding) {
      watch.notePaused();
      return;
    }
    final restart = watch.onStreamEnded();
    if (!restart || !_allowRecover()) return;
    if (_radioUnderTest) return;
    _startPlugin();
  }

  bool _allowRecover() {
    final now = DateTime.now();
    if (_lostBurstAt == null || now.difference(_lostBurstAt!) > const Duration(seconds: 5)) {
      _lostBurstAt = now;
      _lostBurst = 0;
    }
    _lostBurst += 1;
    return _lostBurst <= 3;
  }

  @visibleForTesting
  void debugPrepare({
    required bool scanEnabled,
    required bool scanningNow,
    required bool alive,
  }) {
    _holding = false;
    enabled = scanEnabled;
    scanning = scanningNow;
    watch.enabled = scanEnabled;
    watch.scanning = scanningNow;
    watch.subscriptionAlive = alive;
    watch.recoveries = 0;
    _lostBurst = 0;
    _lostBurstAt = null;
  }

  @visibleForTesting
  void debugStreamEnded() => _onScanLost(_listenGeneration);

  Future<void> stopScan() async {
    _holding = true;
    _setEnabled(false);
    await _retireListen();
    try {
      await _beaconsPlugin.stopScan();
    } catch (error) {
      debugPrint('Beacon: $error');
    }
    scanning = false;
    watch.notePaused();
    session.clear();
  }

  double calculateDistance(int rssi, int txPower) {
    if (rssi == 0) return double.infinity;
    final ratio = rssi * 1.0 / txPower;
    if (ratio < 1.0) {
      return pow(ratio, 10).toDouble();
    }
    return 0.89976 * pow(ratio, 7.7095) + 0.111;
  }
}
