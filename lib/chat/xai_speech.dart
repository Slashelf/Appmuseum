/// Pedido de voz a xAI. La clave viaja solo en la cabecera.
class XaiSpeech {
  static final endpoint = Uri.parse('https://api.x.ai/v1/tts');

  /// `es-MX`, `en` o `de`. El portugués usa el español de la casa.
  static String language(String? raw) {
    final code = raw?.trim().toLowerCase() ?? '';
    if (code.startsWith('en')) return 'en';
    if (code.startsWith('de')) return 'de';
    return 'es-MX';
  }

  static Map<String, dynamic> body(
    String text, {
    required String voiceId,
    String? languageCode,
  }) {
    return {
      'text': text,
      'voice_id': voiceId,
      'language': language(languageCode),
    };
  }

  static Map<String, String> headers(String apiKey) {
    return {
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'audio/mpeg',
    };
  }

  /// Texto seguro para un registro: la clave no aparece.
  static String redacted(Map<String, String> headers) {
    final hidden = Map<String, String>.of(headers);
    if (hidden.containsKey('Authorization')) {
      hidden['Authorization'] = 'Bearer oculto';
    }
    return hidden.toString();
  }
}
