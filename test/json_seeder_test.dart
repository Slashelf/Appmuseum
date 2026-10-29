import 'dart:convert';

import 'package:app_guia_v1/data/local/app_database.dart';
import 'package:app_guia_v1/data/local/json_seeder.dart';
import 'package:app_guia_v1/data/local_content_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('json content is copied once and keeps ids, images and coordinates', () async {
    final database = await AppDatabase.open(path: inMemoryDatabasePath);
    final seeder = JsonSeeder(database);
    await seeder.seedIfNeeded();
    await seeder.seedIfNeeded();

    final repository = LocalContentRepository(database);
    final places = await repository.getPlaces();
    final source = jsonDecode(await rootBundle.loadString('assets/data/objects.json')) as List;

    expect(places, hasLength(source.length));
    expect(places.map((place) => place.id), containsAll(['D5:E0:59:B6:6F:C8', 'DD:20:87:F7:72:14', 'OBJ005']));

    final evangelists = places.firstWhere((place) => place.id == 'D5:E0:59:B6:6F:C8');
    expect(evangelists.name, 'San Mateo y los cuatro evangelistas');
    expect(evangelists.imageUrl, 'assets/images/item1/CriptaFranci.jpg');
    expect(evangelists.extraImages, isNotEmpty);
    expect(evangelists.galleryImages, isNotEmpty);
    expect(evangelists.localized('en').name, 'Saint Matthew and the four evangelists');
    expect(evangelists.localized('de').name, isNot(evangelists.name));
    expect(evangelists.localized('fr').name, evangelists.name);

    final recommended = await repository.getRecommended();
    expect(recommended, hasLength(4));
    final francis = recommended.firstWhere(
      (item) => item.title == 'San Francisco de Asís',
    );
    expect(francis.latitude, closeTo(-19.5886111, 0.000001));
    expect(francis.longitude, closeTo(-65.7541667, 0.000001));
    expect(francis.celular, '26222777');
    expect(francis.localized('en').title, isNot(francis.title));

    final series = recommended.firstWhere(
      (item) => item.title == 'San Mateo y los cuatro evangelistas',
    );
    expect(series.sourceId, 'sf1');
    expect(series.yearFounded, 1724);
    expect(series.extraImages, isNotEmpty);

    final carousel = await repository.getCarousel();
    final carouselSource = jsonDecode(
      await rootBundle.loadString('assets/data/object_carousel.json'),
    ) as Map;
    expect(carousel, isNotNull);
    expect(carousel!.description, hasLength((carouselSource['description'] as List).length));
    expect(carousel.description.first, startsWith('La Casa Nacional de la Moneda'));
    expect(carousel.images.single, contains('cloudinary'));
    expect(carousel.localized('en').description.first, isNot(carousel.description.first));

    final byMac = await repository.findByCode('d5:e0:59:b6:6f:c8');
    expect(byMac?.id, 'D5:E0:59:B6:6F:C8');

    await database.close();
  });
}
