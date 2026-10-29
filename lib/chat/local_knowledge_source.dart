import '../data/content_repository.dart';
import '../models/object_model.dart';
import 'chat_faq.dart';
import 'knowledge_source.dart';
import 'place_card.dart';

class LocalKnowledgeSource implements KnowledgeSource {
  final ContentRepository repository;

  /// Ficha de la casa cuando no hay beacon. No inventa precios ni horarios.
  static const houseFact =
      'Casa Nacional de la Moneda, Calle Ayacucho, entre Quijarro y Bustillos. '
      'Teléfono 26222777. Lunes a viernes 8:30 a 16:30; sábado y domingo 9:00 a 13:00. '
      'Entrada: 20 Bs nacionales, 70 Bs extranjeros.';

  LocalKnowledgeSource(this.repository);

  /// Con beacon, solo esa ficha. Sin beacon, la casa y su ficha de visita.
  @override
  Future<List<KnowledgeSnippet>> search({
    required String question,
    required String languageCode,
    String? currentPlaceId,
  }) async {
    final id = currentPlaceId?.trim() ?? '';
    if (id.isEmpty) return [await _house(languageCode)];
    final places = await repository.getPlaces();
    final card = _placeCard(places, id, languageCode);
    if (card == null) return const [];
    return [card];
  }

  Future<KnowledgeSnippet> _house(String languageCode) async {
    final carousel = await repository.getCarousel();
    final text = carousel?.localized(languageCode);
    final title = text?.title.trim().isNotEmpty == true
        ? text!.title.trim()
        : 'Casa Nacional de la Moneda';
    final paragraphs = text?.description ?? const <String>[];
    final body = [
      ...paragraphs.where((paragraph) => paragraph.trim().isNotEmpty),
      houseFact,
    ].join('\n\n');
    return KnowledgeSnippet(
      id: 'casa-nacional',
      title: title,
      body: body,
      fact: body,
      focus: AnswerFocus.here,
      score: 1,
    );
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
