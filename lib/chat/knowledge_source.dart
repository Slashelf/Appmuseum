import 'chat_faq.dart';

class KnowledgeSnippet {
  final String id;
  final String title;
  final String body;
  final String fact;
  final AnswerFocus focus;
  final int score;

  const KnowledgeSnippet({
    required this.id,
    required this.title,
    required this.body,
    required this.fact,
    required this.focus,
    required this.score,
  });
}

/// Búsqueda de textos de la guía. Otra implementación puede usar una API.
abstract class KnowledgeSource {
  Future<List<KnowledgeSnippet>> search({
    required String question,
    required String languageCode,
    String? currentPlaceId,
  });
}
