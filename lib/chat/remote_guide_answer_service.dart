import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'chat_message.dart';
import 'guide_answer_service.dart';
import 'knowledge_source.dart';
import 'spoken_sentences.dart';

/// Redacta con DeepSeek a partir de la ficha oficial y los últimos mensajes.
///
/// La clave llega por `--dart-define=DEEPSEEK_API_KEY` o por Ajustes.
/// No se escribe en el código. Sin clave, [tryAsk] devuelve null.
class RemoteGuideAnswerService implements GuideAnswerService {
  String apiKey;
  final GuideAnswerService fallback;

  static const endpoint = 'https://api.deepseek.com/chat/completions';
  static const model = 'deepseek-flash';

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
      'max_tokens': spoken ? maxSpokenTokens : maxReplyTokens,
      'thinking': {'type': 'disabled'},
      'messages': [
        {
          'role': 'system',
          'content': _systemPrompt(
            placeName: where.isEmpty ? 'ninguna exhibición elegida' : where,
            officialData: _officialData(snippets),
            summary: summary,
            spoken: spoken,
            languageCode: languageCode,
          ),
        },
        ...dialogue,
      ],
    };
  }

  Future<String> _ask({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required List<ChatMessage> history,
    required String placeName,
    required String summary,
  }) async {
    final body = buildBody(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
      summary: summary,
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
      if (decoded is! Map<String, dynamic>) return '';
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return '';
      final first = choices.first;
      if (first is! Map) return '';
      final message = first['message'];
      if (message is! Map) return '';
      return message['content']?.toString() ?? '';
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
    final body = buildBody(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
      summary: summary,
      spoken: true,
      dialogueLimit: dialogueLimit,
    );
    body['stream'] = true;
    final client = HttpClient();
    final buffer = SpokenSentenceBuffer();
    final collected = StringBuffer();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${apiKey.trim()}');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        final raw = await response.transform(utf8.decoder).join();
        throw _failure(response.statusCode, raw);
      }
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final piece = DeepSeekSse.delta(line);
        if (piece == null || piece.isEmpty) continue;
        collected.write(piece);
        for (final sentence in buffer.add(piece)) {
          onSentence(sentence);
        }
      }
      final rest = buffer.flush();
      if (rest != null) onSentence(rest);
      final text = collected.toString().trim();
      return text.isEmpty ? null : text;
    } finally {
      client.close(force: true);
    }
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

  /// Texto fijo. El resumen y la ficha van al final para reutilizar esta parte.
  static const _fixedInstructions =
      'Eres un guía de museo de Potosí Memoriam, con años de experiencia y pasión por la historia. '
      'Conversas con un visitante frente a una exhibición de fotos e imágenes. '
      'El visitante no está en el lugar real: está viendo la exhibición.\n'
      'Cómo hablas:\n'
      '- Como una persona real, cálida y natural. Varía cómo empiezas cada respuesta; nunca uses la misma frase de inicio dos veces seguidas.\n'
      '- Nunca digas "estás aquí", "te encuentras en" ni "bienvenido a". Tampoco repitas el nombre de la exhibición en cada respuesta.\n'
      '- No repitas datos que ya dijiste en esta conversación; si el visitante vuelve a preguntar, profundiza o da otro ángulo.\n'
      '- Relaciona, cuando venga al caso, con lo que el visitante ya vio o preguntó.\n'
      '- Cuenta las cosas con lógica: qué pasó, por qué importa y un detalle curioso si viene al caso.\n'
      '- Pregunta concreta: responde lo preguntado, directo, en 2 o 3 frases como máximo. Pregunta general: resume lo más interesante en 6 a 8 frases. Nunca copies toda la información. Solo amplía si el usuario lo pide.\n'
      '- No termines siempre con una pregunta; hazlo solo a veces, y cada vez distinta.\n'
      '- Si la voz está activa, usa frases cortas, sin listas, símbolos, emojis ni paréntesis, y escribe los años para que se lean en voz alta.\n'
      '- Responde siempre en el idioma en que te habla el visitante; si cambia de idioma, cámbialo tú también.\n'
      'Qué cuentas:\n'
      '- Usa la ficha como base. Puedes ampliarla con conocimiento histórico y cultural confiable, siempre enfocado en esta exhibición, y con cautela si no estás seguro. Si no estás seguro de un dato, no lo inventes.\n'
      '- Los horarios, precios, direcciones y contactos solo pueden salir de la información oficial.\n'
      '- Enfócate solo en la exhibición actual. Si preguntan por otro lugar u otro tema (por ejemplo, otra ciudad o un tema que no está en la ficha), responde solo si tiene una relación histórica directa con esta exhibición, y explica esa relación. Si no la tiene, indica amablemente que puedes ayudar con esta exhibición y que la otra información está en su propio punto de la exhibición.';

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
