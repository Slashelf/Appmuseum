/// Pedido a ElevenLabs. La clave viaja solo en la cabecera, nunca en el cuerpo.
///
/// No hay un id de voz fijo: Daniel es una voz inglesa. El id lo elige
/// Ajustes o, si está vacío, el listado oficial de voces premade.
class ElevenLabsSpeech {
  static const model = 'eleven_flash_v2_5';

  static Uri streamUri(String voice) {
    return Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/$voice/stream'
      '?output_format=mp3_22050_32',
    );
  }

  /// `es`, `en`, `de` o `pt`. Null si el código no es uno de esos.
  static String? normalizeLanguage(String? raw) {
    final code = raw?.trim().toLowerCase() ?? '';
    if (code.startsWith('pt')) return 'pt';
    if (code.startsWith('en')) return 'en';
    if (code.startsWith('de')) return 'de';
    if (code.startsWith('es')) return 'es';
    return null;
  }

  static Map<String, dynamic> body(
    String text, {
    String? previousText,
    String? languageCode,
  }) {
    final payload = <String, dynamic>{
      'text': text,
      'model_id': model,
      'voice_settings': {
        'stability': 0.4,
        'similarity_boost': 0.75,
        'style': 0.35,
        'use_speaker_boost': true,
        'speed': 1.0,
      },
    };
    final language = normalizeLanguage(languageCode);
    if (language != null) payload['language_code'] = language;
    final previous = previousText?.trim() ?? '';
    if (previous.isNotEmpty) payload['previous_text'] = previous;
    return payload;
  }

  static Map<String, String> headers(String apiKey) {
    return {
      'xi-api-key': apiKey.trim(),
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'audio/mpeg',
    };
  }

  /// Texto seguro para un registro: la clave no aparece.
  static String redacted(Map<String, String> headers) {
    final hidden = Map<String, String>.of(headers);
    if (hidden.containsKey('xi-api-key')) hidden['xi-api-key'] = 'oculto';
    return hidden.toString();
  }
}
