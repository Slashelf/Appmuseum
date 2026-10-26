import '../models/object_carousel_model.dart';
import '../models/object_model.dart';
import '../models/recommended_model.dart';
import 'content_repository.dart';

/// Hueco para una API REST y una base de servidor.
/// No está conectado. La guía sigue leyendo solo la base local.
class RemoteContentRepository implements ContentRepository {
  @override
  Future<List<ObjectModel>> getPlaces() {
    throw UnimplementedError('La API remota todavía no está conectada.');
  }

  @override
  Future<ObjectModel?> findByCode(String code) {
    throw UnimplementedError('La API remota todavía no está conectada.');
  }

  @override
  Future<List<RecommendedModel>> getRecommended() {
    throw UnimplementedError('La API remota todavía no está conectada.');
  }

  @override
  Future<ObjectCarousel?> getCarousel() {
    throw UnimplementedError('La API remota todavía no está conectada.');
  }

  @override
  Future<void> savePendingComment(PendingComment comment) {
    throw UnimplementedError('La API remota todavía no está conectada.');
  }
}
