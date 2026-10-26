/// Junta los fragmentos del modelo y suelta cada frase en cuanto cierra.
class SpokenSentenceBuffer {
  String _pending = '';

  List<String> add(String chunk) {
    if (chunk.isEmpty) return const [];
    _pending += chunk;
    final ready = <String>[];
    while (true) {
      final end = _boundary(_pending);
      if (end < 0) break;
      final sentence = _pending.substring(0, end).trim();
      _pending = _pending.substring(end).trimLeft();
      if (sentence.isNotEmpty) ready.add(sentence);
    }
    return ready;
  }

  /// Lo que quedó al cerrar el flujo, aunque no termine en punto.
  String? flush() {
    final rest = _pending.trim();
    _pending = '';
    if (rest.isEmpty) return null;
    return rest;
  }

  /// Corta después de un punto, signo de cierre o pregunta seguido de espacio.
  int _boundary(String text) {
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char != '.' && char != '!' && char != '?' && char != '…') continue;
      if (i + 1 >= text.length) return -1;
      if (RegExp(r'\s').hasMatch(text[i + 1])) return i + 1;
    }
    return -1;
  }
}
