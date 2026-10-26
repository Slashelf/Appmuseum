import 'package:sqflite/sqflite.dart';

import '../models/object_carousel_model.dart';
import '../models/object_model.dart';
import '../models/recommended_model.dart';
import 'content_repository.dart';

class LocalContentRepository implements ContentRepository {
  final Database database;

  LocalContentRepository(this.database);

  @override
  Future<List<ObjectModel>> getPlaces() async {
    final places = await database.query('places');
    final translations = await database.query('place_translations');
    final images = await database.query('place_images', orderBy: 'sort ASC');

    return places.map((row) {
      final id = row['id'] as String;
      final texts = <String, Map<String, String>>{};
      for (final item in translations.where((line) => line['place_id'] == id)) {
        texts[item['locale'] as String] = {
          'name': item['name']?.toString() ?? '',
          'name2': item['name2']?.toString() ?? '',
          'description': item['description']?.toString() ?? '',
          'cryptDescription': item['crypt_description']?.toString() ?? '',
          'location': item['location']?.toString() ?? '',
          'direccion': item['direccion']?.toString() ?? '',
          'openingHours': item['opening_hours']?.toString() ?? '',
          'architecturalStyle': item['architectural_style']?.toString() ?? '',
          'historicalNotes': item['historical_notes']?.toString() ?? '',
          'entranceFee': item['entrance_fee']?.toString() ?? '',
          'category': item['category']?.toString() ?? '',
        };
      }
      final ownImages = images.where((image) => image['place_id'] == id);
      List<String> ofKind(String kind) => ownImages
          .where((image) => image['kind'] == kind)
          .map((image) => image['path'] as String)
          .toList();
      final spanish = texts['es'] ?? const {};
      return ObjectModel(
        id: id,
        name: spanish['name'] ?? '',
        name2: spanish['name2'] ?? '',
        description: spanish['description'] ?? '',
        cryptDescription: spanish['cryptDescription'] ?? '',
        imageUrl: ofKind('main').isEmpty ? '' : ofKind('main').first,
        imageUrl2: ofKind('main2').isEmpty ? '' : ofKind('main2').first,
        extraImages: ofKind('extra'),
        galleryImages: ofKind('gallery'),
        location: spanish['location'],
        direccion: spanish['direccion'],
        celular: row['celular'] as String?,
        openingHours: spanish['openingHours'],
        yearFounded: row['year_founded'] as int?,
        yearCompleted: row['year_completed'] as int?,
        architecturalStyle: spanish['architecturalStyle'],
        historicalNotes: spanish['historicalNotes'],
        entranceFee: spanish['entranceFee'],
        tourAvailable: row['tour_available'] == 1,
        category: spanish['category'],
        relatedObjectId: row['related_object_id'] as String?,
        translations: texts,
      );
    }).toList();
  }

  @override
  Future<ObjectModel?> findByCode(String code) async {
    final needle = code.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final places = await getPlaces();
    for (final place in places) {
      if (place.id.toLowerCase() == needle) return place;
    }
    final beacons = await database.query('beacons');
    for (final beacon in beacons) {
      final mac = beacon['mac']?.toString().toLowerCase();
      if (mac != null && mac == needle) {
        final placeId = beacon['place_id'].toString();
        for (final place in places) {
          if (place.id.toLowerCase() == placeId.toLowerCase()) return place;
        }
      }
    }
    return null;
  }

  @override
  Future<List<RecommendedModel>> getRecommended() async {
    final rows = await database.query('recommendations');
    final translations = await database.query('recommendation_translations');
    final images = await database.query('recommendation_images', orderBy: 'sort ASC');
    return rows.map((row) {
      final id = row['id'] as int;
      final texts = <String, Map<String, String>>{};
      for (final item in translations.where((line) => line['recommendation_id'] == id)) {
        texts[item['locale'] as String] = {
          'title': item['title']?.toString() ?? '',
          'location': item['location']?.toString() ?? '',
          'description': item['description']?.toString() ?? '',
          'openingHours': item['opening_hours']?.toString() ?? '',
        };
      }
      final spanish = texts['es'] ?? const {};
      return RecommendedModel(
        title: spanish['title'] ?? '',
        imageUrl: row['image_url'] as String? ?? '',
        location: spanish['location'] ?? '',
        description: spanish['description'] ?? '',
        latitude: (row['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (row['longitude'] as num?)?.toDouble() ?? 0,
        altitude: (row['altitude'] as num?)?.toDouble() ?? 0,
        openingHours: spanish['openingHours'] ?? '',
        sourceId: row['source_id'] as String?,
        celular: row['celular'] as String?,
        direccion: row['direccion'] as String?,
        yearFounded: row['year_founded'] as int?,
        yearCompleted: row['year_completed'] as int?,
        architecturalStyle: row['architectural_style'] as String?,
        historicalNotes: row['historical_notes'] as String?,
        entranceFee: row['entrance_fee'] as String?,
        category: row['category'] as String?,
        extraImages: images
            .where((image) => image['recommendation_id'] == id)
            .map((image) => image['path'] as String)
            .toList(),
        translations: texts,
      );
    }).toList();
  }

  @override
  Future<ObjectCarousel?> getCarousel() async {
    final titles = await database.query('carousel_titles');
    if (titles.isEmpty) return null;
    final paragraphs = await database.query(
      'carousel_paragraphs',
      orderBy: 'sort ASC',
    );
    final images = await database.query('carousel_images', orderBy: 'sort ASC');
    final titlesByLocale = <String, String>{};
    for (final row in titles) {
      titlesByLocale[row['locale'] as String] = row['title'] as String;
    }
    final paragraphsByLocale = <String, List<String>>{};
    for (final row in paragraphs) {
      paragraphsByLocale.putIfAbsent(row['locale'] as String, () => []);
      paragraphsByLocale[row['locale'] as String]!.add(row['paragraph'] as String);
    }
    return ObjectCarousel(
      title: titlesByLocale['es'] ?? titlesByLocale.values.first,
      description: paragraphsByLocale['es'] ?? const [],
      images: images.map((row) => row['path'] as String).toList(),
      paragraphsByLocale: paragraphsByLocale,
      titlesByLocale: titlesByLocale,
    );
  }

  @override
  Future<void> savePendingComment(PendingComment comment) {
    return database.insert('contact_outbox', {
      'name': comment.name,
      'email': comment.email,
      'comment': comment.comment,
      'rating': comment.rating,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
