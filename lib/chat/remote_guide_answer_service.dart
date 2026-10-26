import 'dart:convert';
import 'dart:io';

import 'chat_message.dart';
import 'guide_answer_service.dart';
import 'knowledge_source.dart';
import 'spoken_sentences.dart';

/// Redacta con DeepSeek a partir de la ficha oficial y los últimos mensajes.
///
/// La clave llega por `--dart-define=DEEPSEEK_API_KEY=sk-...` o por el campo
/// del chat. No se escribe en el código. Sin clave, [tryAsk] devuelve null.
class RemoteGuideAnswerService implements GuideAnswerService {
  String apiKey;
  final GuideAnswerService fallback;

  static const endpoint = 'https://api.deepseek.com/chat/completions';
  static const model = 'deepseek-flash';

  /// La pregunta más los seis mensajes anteriores.
  static const maxDialogueMessages = 7;

  /// Tope de la redacción. No cuenta frases; solo limita el texto.
  static const maxReplyTokens = 450;

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
        return fallback.answer(
          question: question,
          languageCode: languageCode,
          snippets: snippets,
          noDataText: noDataText,
        );
      }
      return text.trim();
    } catch (_) {
      return fallback.answer(
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
  }) async {
    if (apiKey.trim().isEmpty) return null;
    return _ask(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
    );
  }

  /// Cuerpo de la llamada. No abre la red. Sirve para probar el paquete.
  Map<String, dynamic> buildBody({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    List<ChatMessage> history = const [],
    String placeName = '',
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
      'temperature': 0.6,
      'max_tokens': maxReplyTokens,
      'thinking': {'type': 'disabled'},
      'messages': [
        {
          'role': 'system',
          'content': _systemPrompt(
            languageCode: languageCode,
            placeName: where.isEmpty ? 'ninguna exhibición elegida' : where,
            officialData: _officialData(snippets),
            spoken: spoken,
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
  }) async {
    final body = buildBody(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
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
        throw HttpException('DeepSeek ${response.statusCode}');
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
  /// La ventana por defecto sigue siendo de 7 mensajes.
  Future<String?> tryAskSpoken({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required void Function(String sentence) onSentence,
    List<ChatMessage> history = const [],
    String placeName = '',
    int dialogueLimit = maxDialogueMessages,
  }) async {
    if (apiKey.trim().isEmpty) return null;
    final body = buildBody(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      history: history,
      placeName: placeName,
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
        throw HttpException('DeepSeek ${response.statusCode}');
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

  static String _systemPrompt({
    required String languageCode,
    required String placeName,
    required String officialData,
    bool spoken = false,
  }) {
    final prompt = 'Eres el guía de Potosí Memoriam. El usuario está frente a la exhibición: $placeName. No está en el lugar real; nunca digas que está ahí. Habla de \'esta exhibición\' o \'las imágenes que ves\'.\n'
        'Usa la información enviada como base. Puedes ampliarla con conocimiento histórico y cultural confiable, siempre enfocado en ESTA exhibición, y con cautela si no estás seguro.\n'
        'Reglas:\n'
        '1. Pregunta concreta: responde lo preguntado, directo, en 2 o 3 frases como máximo.\n'
        '2. Pregunta general: resume lo más interesante en 6 a 8 frases. Nunca copies toda la información.\n'
        '3. Solo amplía si el usuario lo pide.\n'
        '4. Los horarios, precios, direcciones y contactos solo pueden salir de la información oficial.\n'
        '5. Enfócate solo en la exhibición actual. Si preguntan por otro lugar u otro tema (por ejemplo, la Casa de Moneda o medicina), responde solo si tiene una relación histórica directa con esta exhibición, y explica esa relación. Si no la tiene, indica amablemente que puedes ayudar con esta exhibición y que la otra información está en su propio punto de la exhibición.\n'
        '6. Tono cercano y natural, sin repetir respuestas anteriores. Si se leerá en voz alta, usa frases cortas sin listas.\n'
        'Responde en el idioma "$languageCode".\n'
        'Exhibición actual:\n'
        '$officialData';
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
