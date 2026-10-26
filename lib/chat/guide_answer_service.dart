import 'knowledge_source.dart';

/// Arma la respuesta. La pantalla no sabe si el texto sale de la base o de una API.
abstract class GuideAnswerService {
  Future<String> answer({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
  });
}
