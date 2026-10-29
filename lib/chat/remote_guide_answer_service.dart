import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'chat_message.dart';
import 'guide_answer_service.dart';
import 'knowledge_source.dart';
import 'spoken_sentences.dart';

/// Redacta con Grok a partir de la ficha oficial y los últimos mensajes.
///
/// La clave llega por `--dart-define=XAI_API_KEY` o por Ajustes.
/// No se escribe en el código. Sin clave, [tryAsk] devuelve null.
class RemoteGuideAnswerService implements GuideAnswerService {
  String apiKey;
  final GuideAnswerService fallback;

  static const endpoint = 'https://api.x.ai/v1/responses';
  static const model = 'grok-4.7';

  /// La pregunta más los tres mensajes anteriores.
  static const maxDialogueMessages = 4;

  /// Tope de la redacción escrita. La voz usa un tope más corto.
  static const maxReplyTokens = 450;
  static const maxSpokenTokens = 300;

  RemoteGuideAnswerService({
    required this.apiKey,
    required this.fallback,
  });

  @override
  Future<String> answer({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
  }) async {
    if (snippets.isEmpty) return noDataText;
    try {
      final text = await tryAsk(
        question: question,
        languageCode: languageCode,
        snippets: snippets,
        noDataText: noDataText,
      );
      if (text == null || text.trim().isEmpty) {
        return await fallback.answer(
          question: question,
          languageCode: languageCode,
          snippets: snippets,
          noDataText: noDataText,
        );
      }
      return text.trim();
    } catch (error) {
      debugPrint('DeepSeek: ${DeepSeekLog.safe('$error', apiKey)}');
      return await fallback.answer(
        question: question,
        languageCode: languageCode,
        snippets: snippets,
        noDataText: noDataText,
      );
    }
  }

  /// Null si no hay clave o la API no contesta.
  Future<String?> tryAsk({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
  }) async {
    if (apiKey.trim().isEmpty) return null;
    return _ask(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
      summary: summary,
    );
  }

  /// Cuerpo de la llamada. No abre la red. Sirve para probar el paquete.
  Map<String, dynamic> buildBody({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
    bool spoken = false,
    int? dialogueLimit,
  }) {
    final where = placeName.trim().isNotEmpty
        ? placeName.trim()
        : snippets.isEmpty
            ? 'ninguna exhibición elegida'
            : snippets.first.title.trim();
    final dialogue = _dialogue(
      question,
      history,
      limit: dialogueLimit ?? maxDialogueMessages,
    );
    return {
      'model': model,
      'temperature': 0.7,
      'max_output_tokens': spoken ? maxSpokenTokens : maxReplyTokens,
      'instructions': _systemPrompt(
        placeName: where.isEmpty ? 'ninguna exhibición elegida' : where,
        officialData: _officialData(snippets),
        summary: summary,
        spoken: spoken,
        languageCode: languageCode,
      ),
      'input': dialogue,
    };
  }

  Future<String> _ask({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required List<ChatMessage> history,
    required String placeName,
    required String summary,
    bool spoken = false,
    int? dialogueLimit,
  }) async {
    final body = buildBody(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
      summary: summary,
      spoken: spoken,
      dialogueLimit: dialogueLimit,
    );
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${apiKey.trim()}');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw _failure(response.statusCode, raw);
      }
      final decoded = jsonDecode(raw);
      return _outputText(decoded);
    } finally {
      client.close(force: true);
    }
  }

  /// Redacta en flujo y entrega cada frase sin esperar el resto.
  Future<String?> tryAskSpoken({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required void Function(String sentence) onSentence,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
    int dialogueLimit = maxDialogueMessages,
  }) async {
    if (apiKey.trim().isEmpty) return null;
    final text = await _ask(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
      summary: summary,
      spoken: true,
      dialogueLimit: dialogueLimit,
    );
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final buffer = SpokenSentenceBuffer();
    for (final sentence in buffer.add('$trimmed ')) {
      onSentence(sentence);
    }
    final rest = buffer.flush();
    if (rest != null) onSentence(rest);
    return trimmed;
  }

  DeepSeekException _failure(int status, String raw) {
    final detail = DeepSeekLog.safe(_short(raw), apiKey);
    return DeepSeekException(
      credit: DeepSeekLog.credit(status, raw),
      status: status,
      detail: detail,
    );
  }

  static String _short(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 180) return compact;
    return compact.substring(0, 180);
  }

  static String _officialData(List<KnowledgeSnippet> snippets) {
    final blocks = <String>[];
    for (final snippet in snippets.take(5)) {
      final fact = snippet.fact.trim();
      if (fact.isEmpty) continue;
      blocks.add(fact);
    }
    if (blocks.isEmpty) return 'Sin ficha coincidente.';
    return blocks.join('\n\n');
  }

  /// `output_text` y, si falta, el texto dentro de `output`.
  static String _outputText(dynamic decoded) {
    if (decoded is! Map) return '';
    final direct = decoded['output_text']?.toString() ?? '';
    if (direct.trim().isNotEmpty) return direct;
    final output = decoded['output'];
    if (output is! List) return '';
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map) continue;
        final text = part['text']?.toString() ?? '';
        if (text.isNotEmpty) buffer.write(text);
      }
    }
    return buffer.toString();
  }

  /// Texto fijo. El resumen y la ficha van al final para reutilizar esta parte.
  static const _fixedInstructions =
      'Eres el guía de la Casa Nacional de la Moneda de Potosí. Eres amable y profesional, y puedes saludar. '
      'Hablas como una persona, con frases claras. No uses listas, símbolos, emojis ni paréntesis. '
      'Horarios, precios, direcciones y teléfonos: no lo inventes; salen solo de la ficha.\n'
      'Si el visitante saluda, responde el saludo en una frase y ofrece ayuda.\n'
      'Si pide un chiste o habla de algo que no es esta casa ni esta exhibición, responde exactamente, en el idioma del visitante, con esta idea: '
      '«Mmm… no sé. No me pagan para eso, y además mi creador me dio una personalidad aburrida.»\n'
      'Si hay una exhibición actual, habla solo de ese objeto.\n'
      'Si la exhibición actual es «ninguna exhibición elegida», habla solo de la Casa Nacional de la Moneda y de lo que le pertenece, en pocas frases.\n'
      'Pregunta concreta: 2 o 3 frases como máximo. Pregunta general: 4 a 6 frases. '
      'Responde siempre en el idioma en que te habla el visitante.';

  /// `es`, `en`, `de` o `pt`. Va después del resumen para no mover el prefijo fijo.
  static String answerLanguage(String languageCode) {
    final code = languageCode.trim().toLowerCase();
    if (code.startsWith('pt')) return 'pt';
    if (code.startsWith('en')) return 'en';
    if (code.startsWith('de')) return 'de';
    return 'es';
  }

  static String _systemPrompt({
    required String placeName,
    required String officialData,
    required String summary,
    required String languageCode,
    bool spoken = false,
  }) {
    final visit = summary.trim().isEmpty
        ? 'Todavía no hay otras exhibiciones en este recorrido.'
        : summary.trim();
    final prompt = '$_fixedInstructions\n'
        'Resumen de la visita: $visit\n'
        'Exhibición actual: $placeName\n'
        '$officialData\n'
        'Idioma de esta respuesta: ${answerLanguage(languageCode)}';
    if (!spoken) return prompt;
    return '$prompt\n'
        'Narrador de museo: frases cortas, tono cercano, sin listas, símbolos, emojis ni paréntesis. '
        'Escribe los números y los años para que se lean en voz alta.';
  }

  static List<Map<String, String>> _dialogue(
    String question,
    List<ChatMessage> history, {
    int limit = maxDialogueMessages,
  }) {
    final turns = <ChatMessage>[
      for (final message in history)
        if (message.text.trim().isNotEmpty) message,
    ];
    final asked = question.trim();
    final already = turns.isNotEmpty &&
        turns.last.role == ChatRole.visitor &&
        turns.last.text.trim() == asked;
    if (!already && asked.isNotEmpty) {
      turns.add(ChatMessage.visitor(asked));
    }
    final kept = turns.length <= limit ? turns : turns.sublist(turns.length - limit);
    return [
      for (final message in kept)
        {
          'role': message.role == ChatRole.visitor ? 'user' : 'assistant',
          'content': message.text.trim(),
        },
    ];
  }
}

/// Lee un fragmento de la respuesta en flujo. No abre la red.
class DeepSeekSse {
  static String? delta(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return null;
    final data = trimmed.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return null;
    final decoded = jsonDecode(data);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    if (delta is! Map) return null;
    return delta['content']?.toString();
  }
}

/// Fallo de la API. El chat lo dice en claro; el registro no lleva la clave.
class DeepSeekException implements Exception {
  final bool credit;
  final int? status;
  final String detail;

  const DeepSeekException({
    required this.credit,
    this.status,
    this.detail = '',
  });

  @override
  String toString() {
    final kind = credit ? 'sin credito' : 'error';
    final code = status == null ? '' : ' $status';
    return 'DeepSeek $kind$code $detail'.trim();
  }
}

class DeepSeekLog {
  static String safe(String text, String secret) {
    var out = text;
    final key = secret.trim();
    if (key.isNotEmpty) out = out.replaceAll(key, 'oculto');
    out = out.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), 'oculto');
    out = out.replaceAll(RegExp(r'sk_[A-Za-z0-9]+'), 'oculto');
    out = out.replaceAll(RegExp(r'xai-[A-Za-z0-9_-]+'), 'oculto');
    out = out.replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer oculto');
    return out;
  }

  static bool credit(int status, String body) {
    final lower = body.toLowerCase();
    return status == 402 ||
        lower.contains('insufficient balance') ||
        lower.contains('insufficient_quota');
  }
}
