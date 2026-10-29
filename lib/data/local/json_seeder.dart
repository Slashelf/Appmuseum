import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/beacons/beacon_config.dart';
import '../../models/object_carousel_model.dart';
import '../../models/object_model.dart';
import '../../models/recommended_model.dart';

class JsonSeeder {
  static const seedVersion = '4';

  final Database database;

  JsonSeeder(this.database);

  Future<void> seedIfNeeded() async {
    final current = await database.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['seed_version'],
    );
    if (current.isNotEmpty && current.first['value'] == seedVersion) return;

    final objects = jsonDecode(await rootBundle.loadString('assets/data/objects.json'));
    final recommended = jsonDecode(await rootBundle.loadString('assets/data/recommended.json'));
    final view = jsonDecode(await rootBundle.loadString('assets/data/view.json'));
    final carousel = jsonDecode(await rootBundle.loadString('assets/data/object_carousel.json'));
    final i18n = jsonDecode(await rootBundle.loadString('assets/data/i18n/content_i18n.json'));

    await database.transaction((txn) async {
      await _clear(txn);
      await _seedPlaces(txn, objects as List, i18n as Map);
      await _seedRecommended(txn, recommended as List, view as List, i18n);
      await _seedCarousel(txn, carousel as Map, i18n);
      await txn.insert('meta', {'key': 'seed_version', 'value': seedVersion});
    });
  }

  Future<void> _clear(Transaction txn) async {
    for (final table in [
      'place_translations',
      'place_images',
      'beacons',
      'places',
      'recommendation_translations',
      'recommendation_images',
      'recommendations',
      'carousel_images',
      'carousel_titles',
      'carousel_paragraphs',
    ]) {
      await txn.delete(table);
    }
  }

  Future<void> _seedPlaces(Transaction txn, List objects, Map i18n) async {
    final mac = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    for (final raw in objects) {
      final place = ObjectModel.fromJson(Map<String, dynamic>.from(raw as Map));
      await txn.insert('places', {
        'id': place.id,
        'year_founded': place.yearFounded,
        'year_completed': place.yearCompleted,
        'tour_available': (place.tourAvailable ?? false) ? 1 : 0,
        'related_object_id': place.relatedObjectId,
        'celular': place.celular,
      });

      final locales = <String, Map<String, String>>{
        'es': Map<String, String>.from(place.translations['es'] ?? {}),
      };
      final extra = (i18n['places'] as Map?)?[place.id];
      if (extra is Map) {
        extra.forEach((locale, value) {
          if (value is Map) {
            locales[locale.toString()] = value.map(
              (key, text) => MapEntry(key.toString(), text?.toString() ?? ''),
            );
          }
        });
      }
      for (final entry in locales.entries) {
        final text = entry.value;
        await txn.insert('place_translations', {
          'place_id': place.id,
          'locale': entry.key,
          'name': text['name'],
          'name2': text['name2'],
          'description': text['description'],
          'crypt_description': text['cryptDescription'],
          'location': text['location'],
          'direccion': text['direccion'],
          'opening_hours': text['openingHours'],
          'architectural_style': text['architecturalStyle'],
          'historical_notes': text['historicalNotes'],
          'entrance_fee': text['entranceFee'],
          'category': text['category'],
        });
      }

      await _insertImages(txn, place.id, 'main', [place.imageUrl]);
      await _insertImages(txn, place.id, 'main2', [place.imageUrl2]);
      await _insertImages(txn, place.id, 'extra', place.extraImages);
      await _insertImages(txn, place.id, 'gallery', place.galleryImages);

      await txn.insert('beacons', {
        'place_id': place.id,
        'mac': mac.hasMatch(place.id) ? place.id : null,
        'uuid': BeaconConfig.uuid,
        'rssi_enter': BeaconConfig.rssiEnter,
      });
    }
  }

  Future<void> _insertImages(
    Transaction txn,
    String placeId,
    String kind,
    List<String> paths,
  ) async {
    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      if (path.trim().isEmpty) continue;
      await txn.insert('place_images', {
        'place_id': placeId,
        'kind': kind,
        'path': path,
        'sort': index,
      });
    }
  }

  Future<void> _seedRecommended(
    Transaction txn,
    List recommended,
    List view,
    Map i18n,
  ) async {
    final viewByTitle = <String, Map<String, dynamic>>{};
    for (final raw in view) {
      final item = Map<String, dynamic>.from(raw as Map);
      viewByTitle[(item['title'] ?? '').toString()] = item;
    }

    for (final raw in recommended) {
      final merged = Map<String, dynamic>.from(raw as Map);
      final viewItem = viewByTitle[(merged['title'] ?? '').toString()];
      if (viewItem != null) {
        for (final key in [
          'id',
          'extraImages',
          'yearFounded',
          'yearCompleted',
          'architecturalStyle',
          'historicalNotes',
          'entranceFee',
          'tourAvailable',
          'category',
          'relatedObjectId',
          'celular',
          'direccion',
        ]) {
          if (merged[key] == null && viewItem[key] != null) {
            merged[key] = viewItem[key];
          }
        }
      }

      final model = RecommendedModel.fromJson(merged);
      final id = await txn.insert('recommendations', {
        'source_id': model.sourceId,
        'match_title': merged['title']?.toString() ?? model.title,
        'image_url': model.imageUrl,
        'latitude': model.latitude,
        'longitude': model.longitude,
        'altitude': model.altitude,
        'celular': model.celular,
        'direccion': model.direccion,
        'year_founded': model.yearFounded,
        'year_completed': model.yearCompleted,
        'tour_available': viewItem?['tourAvailable'] == true ? 1 : 0,
        'related_object_id': viewItem?['relatedObjectId']?.toString(),
        'entrance_fee': model.entranceFee,
        'category': model.category,
        'architectural_style': model.architecturalStyle,
        'historical_notes': model.historicalNotes,
      });

      final locales = <String, Map<String, String>>{
        'es': Map<String, String>.from(model.translations['es'] ?? {}),
      };
      final extra = (i18n['recommendations'] as Map?)?[model.title];
      if (extra is Map) {
        extra.forEach((locale, value) {
          if (value is Map) {
            locales[locale.toString()] = value.map(
              (key, text) => MapEntry(key.toString(), text?.toString() ?? ''),
            );
          }
        });
      }
      for (final entry in locales.entries) {
        final text = entry.value;
        await txn.insert('recommendation_translations', {
          'recommendation_id': id,
          'locale': entry.key,
          'title': text['title'],
          'location': text['location'],
          'description': text['description'],
          'opening_hours': text['openingHours'],
        });
      }
      for (var index = 0; index < model.extraImages.length; index++) {
        await txn.insert('recommendation_images', {
          'recommendation_id': id,
          'path': model.extraImages[index],
          'sort': index,
        });
      }
    }
  }

  Future<void> _seedCarousel(Transaction txn, Map raw, Map i18n) async {
    final carousel = ObjectCarousel.fromJson(Map<String, dynamic>.from(raw));
    for (var index = 0; index < carousel.images.length; index++) {
      await txn.insert('carousel_images', {
        'path': carousel.images[index],
        'sort': index,
      });
    }
    await txn.insert('carousel_titles', {'locale': 'es', 'title': carousel.title});
    for (var index = 0; index < carousel.description.length; index++) {
      await txn.insert('carousel_paragraphs', {
        'locale': 'es',
        'sort': index,
        'paragraph': carousel.description[index],
      });
    }

    final extra = i18n['carousel'];
    if (extra is Map) {
      for (final entry in extra.entries) {
        if (entry.key.toString() == 'es' || entry.value is! Map) continue;
        final value = entry.value as Map;
        final title = value['title']?.toString();
        if (title != null && title.isNotEmpty) {
          await txn.insert('carousel_titles', {
            'locale': entry.key.toString(),
            'title': title,
          });
        }
        final paragraphs = value['paragraphs'];
        if (paragraphs is List) {
          for (var index = 0; index < paragraphs.length; index++) {
            await txn.insert('carousel_paragraphs', {
              'locale': entry.key.toString(),
              'sort': index,
              'paragraph': paragraphs[index].toString(),
            });
          }
        }
      }
    }
  }
}
