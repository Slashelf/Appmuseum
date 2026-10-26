import '../models/object_carousel_model.dart';
import '../models/object_model.dart';
import '../models/recommended_model.dart';
import '../repositories/data_repository.dart';

Future<List<ObjectModel>> loadObjects() {
  return DataRepository.loadAll();
}

Future<List<RecommendedModel>> loadRecommendedObjects() {
  final repository = DataRepository.instance;
  if (repository == null) {
    throw StateError('El repositorio de contenidos no está listo.');
  }
  return repository.getRecommended();
}

Future<ObjectCarousel?> loadObjectCarousel() {
  final repository = DataRepository.instance;
  if (repository == null) {
    throw StateError('El repositorio de contenidos no está listo.');
  }
  return repository.getCarousel();
}
