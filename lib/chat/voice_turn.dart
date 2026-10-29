/// Lo que la pantalla Hablar lleva oído en un turno.
///
/// La hipótesis en curso se reemplaza. Si el reconocedor se corta, lo ya oído
/// se guarda y la frase siguiente se suma, sin repetir el principio.
class VoiceTurn {
  static const endpoint = Duration(milliseconds: 2400);
  static const retryLimit = 3;

  String committed = '';
  String live = '';
  int failures = 0;

  String get text {
    final saved = committed.trim();
    final current = live.trim();
    if (saved.isEmpty) return current;
    if (current.isEmpty) return saved;
    return '$saved $current';
  }

  bool get isEmpty => text.isEmpty;

  void hear(String words) {
    final next = words.trim();
    final saved = committed.trim();
    if (saved.isNotEmpty && (next == saved || next.startsWith('$saved '))) {
      committed = '';
      live = next;
    } else {
      live = next;
    }
    failures = 0;
  }

  /// El reconocedor cerró la sesión. No es el final de la frase.
  void engineStopped() {
    final spoken = text;
    committed = spoken;
    live = '';
  }

  /// Un fallo pasajero. Devuelve verdadero si hay que volver a escuchar.
  bool noteError() {
    failures += 1;
    return failures < retryLimit;
  }

  void reset() {
    committed = '';
    live = '';
    failures = 0;
  }
}
