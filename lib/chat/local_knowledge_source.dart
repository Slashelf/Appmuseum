import '../data/content_repository.dart';
import '../models/object_model.dart';
import 'chat_faq.dart';
import 'knowledge_source.dart';
import 'place_card.dart';

class LocalKnowledgeSource implements KnowledgeSource {
  final ContentRepository repository;

  LocalKnowledgeSource(this.repository);

  /// Solo la exhibición del beacon. Sin beacon no se presta otra ficha.
  @override
  Future<List<KnowledgeSnippet>> search({
    required String question,
    required String languageCode,
    String? currentPlaceId,
  }) async {
    final id = currentPlaceId?.trim() ?? '';
    if (id.isEmpty) return const [];
    final places = await repository.getPlaces();
    final card = _placeCard(places, id, languageCode);
    if (card == null) return const [];
    return [card];
  }

  KnowledgeSnippet? _placeCard(
    List<ObjectModel> places,
    String id,
    String languageCode,
  ) {
    ObjectModel? place;
    for (final item in places) {
      if (item.id == id) place = item;
    }
    if (place == null) return null;
    final text = place.localized(languageCode);
    final title = text.name.trim().isNotEmpty ? text.name : text.name2;
    final fact = PlaceCard.fromPlace(place, languageCode).trim();
    if (fact.isEmpty || title.trim().isEmpty) return null;
    return KnowledgeSnippet(
      id: place.id,
      title: title,
      body: fact,
      fact: fact,
      focus: AnswerFocus.here,
      score: 1,
    );
  }
}
