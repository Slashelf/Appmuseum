import 'dart:async';
import 'dart:io';

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
  final List<void Function(ObjectModel? place)> _placeListeners = [];
  final List<void Function(bool enabled)> _enabledListeners = [];
  List<String>? _iBeaconUUIDs;
  String _permissionDeniedMessage = 'Permisos denegados para escaneo BLE';

  /// Borde del radio. Sale de [BeaconConfig.rssiEnter].
  int rssiThreshold = BeaconConfig.rssiEnter;

  /// Las pruebas pueden fingir que el escaneo nativo no arrancó.
  @visibleForTesting
  bool debugStartResult = true;

  final Set<String> _currentKeys = {};
  ObjectModel? _currentPlace;
  Timer? _lostTimer;
  Timer? _retryTimer;
  int _startAttempts = 0;

  @visibleForTesting
  String? debugLastNotice;

  @visibleForTesting
  int debugRetries = 0;

  /// Avisa el lugar al chat. No sustituye la apertura de la ficha.
  void addPlaceListener(void Function(ObjectModel? place) listener) {
    if (_placeListeners.contains(listener)) return;
    _placeListeners.add(listener);
  }

  void removePlaceListener(void Function(ObjectModel? place) listener) {
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
    _startAttempts = 0;
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
      var hasPermissions = await _beaconsPlugin.checkPermissions();
      if (!hasPermissions) {
        hasPermissions = await _beaconsPlugin.requestPermissions();
        if (!hasPermissions) {
          _onStartFailed(permissionsDenied: true, error: 'permission');
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

      var started = await _requestNativeScan();
      if (!started && !_radioUnderTest && enabled && !_holding) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (enabled && !_holding) started = await _requestNativeScan();
      }
      await _applyNativeStart(started);
    } catch (error) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _onStartFailed(permissionsDenied: false, error: error);
    }
  }

  /// Si el teléfono no empezó a escanear, el radio no queda marcado como activo.
  @visibleForTesting
  Future<void> debugApplyNativeStart(bool started) => _applyNativeStart(started);

  Future<void> _applyNativeStart(bool started) async {
    if (!started) {
      await _retireListen();
      _onStartFailed(permissionsDenied: false, error: 'scan');
      return;
    }
    scanning = true;
    watch.noteStarted();
    _startAttempts = 0;
    _retryTimer?.cancel();
  }

  Future<bool> _requestNativeScan() {
    if (_radioUnderTest) return Future.value(debugStartResult);
    return _beaconsPlugin.startScan(
      iBeaconUUIDs: _iBeaconUUIDs ??
          (Platform.isIOS ? [BeaconConfig.uuid] : <String>[]),
    );
  }

  /// Un fallo que no es de permisos vuelve a intentar mientras el visitante lo dejó encendido.
  void _onStartFailed({required bool permissionsDenied, required Object error}) {
    scanning = false;
    watch.notePaused();
    debugPrint('Beacon: $error');
    if (permissionsDenied) {
      _retryTimer?.cancel();
      _setEnabled(false);
      debugLastNotice = _permissionDeniedMessage;
      _onMessage?.call(_permissionDeniedMessage);
      return;
    }
    if (_holding || !enabled) return;
    _startAttempts += 1;
    debugRetries = _startAttempts;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 4), () {
      if (_radioUnderTest || _holding || !enabled) return;
      _startPlugin();
    });
  }

  /// Pide los permisos de Bluetooth. La decisión final sigue siendo la del
  /// plugin, que es la que ya abre los lugares.
  Future<void> _requestBlePermissions() async {
    if (_radioUnderTest) return;
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

  Future<void> _onDevice(Map<String, dynamic> device) {
    return _ingest(device);
  }

  /// Una lectura. [lookup] existe para las pruebas: en la app se busca el lugar.
  @visibleForTesting
  Future<void> debugIngest(
    Map<String, dynamic> device, {
    DateTime? now,
    Future<ObjectModel?> Function(Map<String, dynamic> device)? lookup,
  }) {
    return _ingest(device, now: now, lookup: lookup);
  }

  Future<void> _ingest(
    Map<String, dynamic> device, {
    DateTime? now,
    Future<ObjectModel?> Function(Map<String, dynamic> device)? lookup,
  }) async {
    final rssi = BeaconIdentity.readRssi(device['rssi']);
    final keys = BeaconIdentity.keysFrom(device);
    if (rssi == null || keys.isEmpty) return;

    final moment = now ?? DateTime.now();
    final primary = keys.first;
    final smoothed = session.smooth(primary, rssi);
    session.reading(keys: keys, rssi: rssi, now: moment, enter: rssiThreshold);

    final openedKeys = <String>[];
    var justOpened = false;
    for (final key in keys) {
      if (session.tryOpen(key, rssi, now: moment, enter: rssiThreshold)) {
        justOpened = true;
        openedKeys.add(key);
      }
    }
    final choice = session.consider(
      primary,
      rssi,
      moment,
      justOpened: justOpened,
      level: smoothed,
    );
    if (choice != ExhibitionChoice.show) {
      for (final key in openedKeys) {
        session.release(key);
      }
      if (choice == ExhibitionChoice.same && rssi >= BeaconConfig.rssiExit) {
        _armLoss();
      }
      return;
    }

    ObjectModel? place;
    try {
      place = await (lookup ?? DataRepository.findByBeacon)(device);
    } catch (error) {
      debugPrint('Beacon: $error');
      place = null;
    }
    if (place == null) {
      for (final key in keys) {
        session.release(key);
      }
      return;
    }
    final samePlace = _currentPlace?.id == place.id;
    session.commitExhibition(primary);
    session.markOpen(place.id);
    _currentPlace = place;
    _currentKeys
      ..clear()
      ..addAll(keys)
      ..add(place.id);
    _armLoss();
    for (final listener in List<void Function(ObjectModel?)>.of(_placeListeners)) {
      listener(place);
    }
    if (samePlace) return;
    _onObjectFound?.call(place);
  }

  void _armLoss() {
    _lostTimer?.cancel();
    _lostTimer = Timer(BeaconConfig.signalLost, _loseExhibition);
  }

  void _loseExhibition() {
    if (_currentPlace == null && _currentKeys.isEmpty) return;
    session.dropExhibition(_currentKeys);
    _currentKeys.clear();
    _currentPlace = null;
    for (final listener in List<void Function(ObjectModel?)>.of(_placeListeners)) {
      listener(null);
    }
  }

  @visibleForTesting
  void debugShow(ObjectModel place, {required List<String> keys}) {
    session.commitExhibition(keys.isEmpty ? place.id : keys.first);
    _currentPlace = place;
    _currentKeys
      ..clear()
      ..addAll(keys)
      ..add(place.id);
    for (final key in _currentKeys) {
      session.markOpen(key);
    }
    _armLoss();
    for (final listener in List<void Function(ObjectModel?)>.of(_placeListeners)) {
      listener(place);
    }
  }

  /// Simula una lectura de la exhibición que ya está abierta, sin buscarla en la base.
  @visibleForTesting
  void debugHearCurrent(int rssi) {
    final key = session.exhibitionKey;
    if (key == null) return;
    final now = DateTime.now();
    final smoothed = session.smooth(key, rssi);
    final choice = session.consider(
      key,
      rssi,
      now,
      justOpened: false,
      level: smoothed,
    );
    if (choice == ExhibitionChoice.same && rssi >= BeaconConfig.rssiExit) {
      _armLoss();
    }
  }

  @visibleForTesting
  void debugStartFailed({required bool permissionsDenied}) {
    _onStartFailed(permissionsDenied: permissionsDenied, error: 'test');
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
    _startAttempts = 0;
    debugRetries = 0;
    _retryTimer?.cancel();
    _lostTimer?.cancel();
  }

  @visibleForTesting
  void debugStreamEnded() => _onScanLost(_listenGeneration);

  Future<void> stopScan() async {
    _holding = true;
    _retryTimer?.cancel();
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
}
