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

    final virgen = places.firstWhere((place) => place.id == 'D5:E0:59:B6:6F:C8');
    expect(virgen.name, 'La Virgen del Cerro');
    expect(virgen.imageUrl, 'assets/images/casa/virgen.jpg');
    expect(virgen.extraImages, isNotEmpty);
    expect(virgen.galleryImages, isNotEmpty);
    expect(virgen.localized('en').name, 'The Virgin of the Mountain');
    expect(virgen.localized('de').name, isNot(virgen.name));
    expect(virgen.localized('fr').name, virgen.name);

    final recommended = await repository.getRecommended();
    expect(recommended, hasLength(4));
    final mask = recommended.firstWhere(
      (item) => item.title == 'El Mascarón',
    );
    expect(mask.latitude, closeTo(-19.5886111, 0.000001));
    expect(mask.longitude, closeTo(-65.7541667, 0.000001));
    expect(mask.celular, '26222777');
    expect(mask.localized('en').title, isNot(mask.title));

    final painting = recommended.firstWhere(
      (item) => item.title == 'La Virgen del Cerro',
    );
    expect(painting.sourceId, 'virgen1');
    expect(painting.yearFounded, 1740);
    expect(painting.extraImages, isNotEmpty);

    final carousel = await repository.getCarousel();
    final carouselSource = jsonDecode(
      await rootBundle.loadString('assets/data/object_carousel.json'),
    ) as Map;
    expect(carousel, isNotNull);
    expect(carousel!.description, hasLength((carouselSource['description'] as List).length));
    expect(carousel.description.first, startsWith('La Casa Nacional de la Moneda'));
    expect(carousel.images, hasLength(3));
    expect(carousel.images.first, contains('fachada.jpg'));
    expect(carousel.localized('en').description.first, isNot(carousel.description.first));

    final byMac = await repository.findByCode('d5:e0:59:b6:6f:c8');
    expect(byMac?.id, 'D5:E0:59:B6:6F:C8');

    await database.close();
  });
}
