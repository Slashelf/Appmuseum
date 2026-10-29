/// Configuración de beacons que la guía ya usa.
class BeaconConfig {
  static const String uuid = 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0';

  /// Señal de la zona: -40 dBm o más fuerte. El RSSI no mide metros.
  static const int rssiNear = -40;

  /// Una lectura de -40 dBm, o más fuerte, abre el lugar.
  static const int rssiEnter = -40;

  /// Más floja que esto, se deja la exhibición actual.
  static const int rssiExit = -45;

  static const Duration signalGrace = Duration(seconds: 8);

  /// Una lectura dentro de la zona abre. No hace falta una segunda.
  static const int confirmReadings = 1;

  /// La segunda lectura puede llegar más floja, todavía dentro del radio exterior.
  static const Duration confirmWindow = Duration(seconds: 12);

  /// Otro beacon puede abrir en cuanto su señal llega al umbral.
  static const Duration openCooldown = Duration.zero;

  /// Promedio de las últimas lecturas antes de comparar la señal.
  static const int smoothCount = 4;

  /// La exhibición nueva tiene que seguir más cerca este tiempo.
  static const Duration switchHold = Duration(seconds: 3);

  /// Sin señal de la exhibición actual, se deja de mostrar.
  static const Duration signalLost = Duration(seconds: 15);
}
