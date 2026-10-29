import 'chat_message.dart';

/// Recuerdo corto de la visita. Vive solo en memoria y se pierde al cerrar la app.
class VisitMemory {
  String _placeId = '';
  String _placeName = '';
  int _boundary = 0;
  final List<String> _lines = [];

  int get boundary => _boundary;

  String get text => _lines.join('\n');

  /// Al cambiar de exhibición conserva el resumen y corta el historial del modelo.
  void rememberPlace(String? id, String name, List<ChatMessage> messages) {
    final next = id ?? '';
    if (next == _placeId) return;
    _fold(messages, messages.length);
    _boundary = messages.length;
    _placeId = next;
    _placeName = name.trim();
  }

  /// Borra el resumen y el corte del historial. La exhibición actual se queda.
  void forgetDialogue() {
    _lines.clear();
    _boundary = 0;
  }

  /// Lo que ya no cabe en la ventana del modelo pasa al resumen.
  void roll(List<ChatMessage> messages, int keep) {
    final end = messages.length - keep;
    if (end <= _boundary) return;
    _fold(messages, end);
    _boundary = end;
  }

  void _fold(List<ChatMessage> messages, int end) {
    if (end <= _boundary || _boundary >= messages.length) return;
    final slice = messages.sublist(_boundary, end.clamp(0, messages.length));
    final line = _line(_placeName, slice);
    if (line == null) return;
    _lines.add(line);
    if (_lines.length > 6) {
      _lines.removeRange(0, _lines.length - 6);
    }
  }

  static String? _line(String name, List<ChatMessage> slice) {
    final questions = <String>[];
    final told = <String>[];
    for (final message in slice) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      if (message.role == ChatRole.visitor) {
        questions.add(_clip(text, 80));
      } else {
        told.add(_clip(_firstSentence(text), 90));
      }
    }
    if (questions.isEmpty && told.isEmpty) return null;
    final where = name.trim().isEmpty ? 'una exhibición' : name.trim();
    final buffer = StringBuffer('Vio $where.');
    if (questions.isNotEmpty) {
      buffer.write(' Le interesó: ${questions.take(3).join('; ')}.');
    }
    if (told.isNotEmpty) {
      buffer.write(' Ya se contó: ${told.take(2).join(' ')}');
    }
    return buffer.toString();
  }

  static String _firstSentence(String text) {
    final match = RegExp(r'^.*?[.!?]').firstMatch(text.trim());
    if (match == null) return text.trim();
    return match.group(0)!;
  }

  static String _clip(String text, int max) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= max) return compact;
    return '${compact.substring(0, max).trim()}…';
  }
}
