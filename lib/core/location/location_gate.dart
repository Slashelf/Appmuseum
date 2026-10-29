import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Comprueba si el GPS del teléfono está encendido y abre sus ajustes.
class LocationGate {
  static const channel = MethodChannel('app.guia/location');

  static Future<bool> servicesOn() async {
    final status = await Permission.locationWhenInUse.serviceStatus;
    return status != ServiceStatus.disabled;
  }

  static Future<void> openSettings() {
    return channel.invokeMethod<void>('openLocationSettings');
  }
}
