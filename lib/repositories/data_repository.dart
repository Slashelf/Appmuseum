import '../core/beacons/beacon_session.dart';
import '../data/content_repository.dart';
import '../models/object_model.dart';

/// Punto de acceso que ya usaban QR, NFC y beacons.
/// La lectura real está en [ContentRepository].
class DataRepository {
  static ContentRepository? instance;

  static void bind(ContentRepository repository) {
    instance = repository;
  }

  static ContentRepository get _repository {
    final current = instance;
    if (current == null) {
      throw StateError('El repositorio de contenidos no está listo.');
    }
    return current;
  }

  static Future<List<ObjectModel>> loadAll() => _repository.getPlaces();

  static Future<ObjectModel?> findByCode(String code) => _repository.findByCode(code);

  static Future<ObjectModel?> findByBeacon(Map<String, dynamic> device) async {
    for (final key in BeaconIdentity.keysFrom(device)) {
      final place = await findByCode(key);
      if (place != null) return place;
    }
    return null;
  }
}
