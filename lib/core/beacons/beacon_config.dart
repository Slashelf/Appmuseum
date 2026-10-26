/// Configuración de beacons que la guía ya usa.
class BeaconConfig {
  static const String uuid = 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0';

  /// Umbral de entrada. Apunta a cerca de medio metro.
  /// Unos 6 dB más estricto que el ajuste anterior de un metro.
  /// El RSSI no mide metros: hay que calibrarlo caminando.
  static const int rssiEnter = -56;

  /// Por debajo de este valor, y solo si se mantiene, el lugar puede volver a abrirse.
  static const int rssiExit = -80;

  static const Duration signalGrace = Duration(seconds: 8);

  /// Una lectura cercana abre el lugar. No se acumulan anuncios.
  static const int confirmReadings = 1;

  static const Duration confirmWindow = Duration(seconds: 6);

  /// Otro beacon puede abrir en cuanto su señal llega al umbral.
  static const Duration openCooldown = Duration.zero;
}
