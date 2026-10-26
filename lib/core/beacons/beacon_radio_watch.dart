/// Decide cuándo volver a encender el radio.
///
/// No borra la exhibición ni la sesión del beacon. Un escaneo sano no se reinicia.
class BeaconRadioWatch {
  bool enabled = false;
  bool scanning = false;
  bool subscriptionAlive = false;
  int recoveries = 0;

  bool get healthy => enabled && scanning && subscriptionAlive;

  /// El visitante cambió de modo. Solo reanuda si el radio no está activo.
  bool onModeChanged() {
    if (!enabled || healthy) return false;
    scanning = false;
    subscriptionAlive = false;
    recoveries++;
    return true;
  }

  /// El flujo del plugin terminó o falló. No vacía la sesión.
  bool onStreamEnded() {
    scanning = false;
    subscriptionAlive = false;
    if (!enabled) return false;
    recoveries++;
    return true;
  }

  void noteStarted() {
    scanning = true;
    subscriptionAlive = true;
  }

  void notePaused() {
    scanning = false;
    subscriptionAlive = false;
  }
}
