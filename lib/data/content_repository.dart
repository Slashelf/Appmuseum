import '../models/object_carousel_model.dart';
import '../models/object_model.dart';
import '../models/recommended_model.dart';

class PendingComment {
  final String name;
  final String email;
  final String comment;
  final int rating;

  const PendingComment({
    required this.name,
    required this.email,
    required this.comment,
    required this.rating,
  });
}

/// Contrato de los contenidos de la guía.
/// Hoy lo cumple la base local. Una API REST puede implementarlo después
/// sin cambiar las pantallas.
abstract class ContentRepository {
  Future<List<ObjectModel>> getPlaces();

  Future<ObjectModel?> findByCode(String code);

  Future<List<RecommendedModel>> getRecommended();

  Future<ObjectCarousel?> getCarousel();

  Future<void> savePendingComment(PendingComment comment);
}
