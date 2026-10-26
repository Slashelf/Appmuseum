import 'chat_faq.dart';
import 'guide_answer_service.dart';
import 'knowledge_source.dart';

/// Dice solo el dato guardado, con una frase corta.
class LocalGuideAnswerService implements GuideAnswerService {
  @override
  Future<String> answer({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
  }) async {
    if (snippets.isEmpty) return noDataText;
    final fact = snippets.first.fact.trim();
    if (fact.isEmpty) return noDataText;
    if (snippets.first.id == 'choice') {
      return ChatFaq.choice(fact, languageCode);
    }
    if (snippets.first.id == 'overview') return fact;
    return ChatFaq.phrase(
      focus: snippets.first.focus,
      fact: fact,
      title: snippets.first.title,
      languageCode: languageCode,
      question: question,
    );
  }
}
