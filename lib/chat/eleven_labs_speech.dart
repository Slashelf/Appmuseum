/// Pedido a ElevenLabs. La clave viaja solo en la cabecera, nunca en el cuerpo.
class ElevenLabsSpeech {
  static const model = 'eleven_flash_v2_5';

  /// Daniel, narrador masculino de las voces predeterminadas.
  static const voiceId = 'onwK4e9ZLuTAKqWW03F9';

  static Uri streamUri(String voice) {
    return Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/$voice/stream'
      '?output_format=mp3_22050_32',
    );
  }

  static Map<String, dynamic> body(String text) {
    return {
      'text': text,
      'model_id': model,
      'voice_settings': {
        'stability': 0.45,
        'similarity_boost': 0.75,
        'style': 0,
        'use_speaker_boost': false,
        'speed': 1.0,
      },
    };
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
