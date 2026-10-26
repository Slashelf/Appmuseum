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

    final sanFrancisco = places.firstWhere((place) => place.id == 'D5:E0:59:B6:6F:C8');
    expect(sanFrancisco.name, 'Criptas de San Francisco');
    expect(sanFrancisco.imageUrl, 'assets/images/item1/CriptaFranci.jpg');
    expect(sanFrancisco.extraImages, isNotEmpty);
    expect(sanFrancisco.galleryImages, isNotEmpty);
    expect(sanFrancisco.localized('en').name, 'Crypts of San Francisco');
    expect(sanFrancisco.localized('de').name, isNot(sanFrancisco.name));
    expect(sanFrancisco.localized('fr').name, sanFrancisco.name);

    final recommended = await repository.getRecommended();
    expect(recommended, hasLength(4));
    final merced = recommended.firstWhere(
      (item) => item.title == 'Museo Mirador Nuestra Señora de la Merced',
    );
    expect(merced.latitude, closeTo(-19.58917797216919, 0.000001));
    expect(merced.longitude, closeTo(-65.7570871755414, 0.000001));
    expect(merced.celular, '26230250');
    expect(merced.localized('en').title, isNot(merced.title));

    final franciscan = recommended.firstWhere(
      (item) => item.title == 'Museo Eclesiástico Franciscano',
    );
    expect(franciscan.sourceId, 'sf1');
    expect(franciscan.yearFounded, 1547);
    expect(franciscan.extraImages, isNotEmpty);

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
