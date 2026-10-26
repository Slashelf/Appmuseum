class ObjectModel {
  final String id;
  final String name;
  final String name2;
  final String description;
  final String cryptDescription; // descripción de la cripta
  final String imageUrl;
  final String imageUrl2;         // imagen principal
  final List<String> extraImages; // imágenes para la primera pantalla (resumen)
  final List<String> galleryImages; // imágenes para la galería
  final String? location;
  final String? direccion;
  final String? celular;
  final String? openingHours;
  final int? yearFounded;
  final int? yearCompleted;
  final String? architecturalStyle;
  final String? historicalNotes;
  final String? entranceFee;
  final bool? tourAvailable;
  final String? category;
  final String? relatedObjectId;
  final Map<String, Map<String, String>> translations;

  ObjectModel({
    required this.id,
    required this.name,
    required this.name2,
    required this.description,
    required this.cryptDescription,
    required this.imageUrl,
    required this.imageUrl2,
    this.extraImages = const [],
    this.galleryImages = const [],
    this.location,
    this.direccion,
    this.celular,
    this.openingHours,
    this.yearFounded,
    this.yearCompleted,
    this.architecturalStyle,
    this.historicalNotes,
    this.entranceFee,
    this.tourAvailable,
    this.category,
    this.relatedObjectId,
    this.translations = const {},
  });

  String _pick(String languageCode, String key, String fallback) {
    final current = translations[languageCode]?[key];
    if (current != null && current.trim().isNotEmpty) return current;
    final spanish = translations['es']?[key];
    if (spanish != null && spanish.trim().isNotEmpty) return spanish;
    return fallback;
  }

  String? _pickNullable(String languageCode, String key, String? fallback) {
    final current = translations[languageCode]?[key];
    if (current != null && current.trim().isNotEmpty) return current;
    final spanish = translations['es']?[key];
    if (spanish != null && spanish.trim().isNotEmpty) return spanish;
    return fallback;
  }

  /// Copia con los textos del idioma pedido. Si falta una frase, usa español.
  ObjectModel localized(String languageCode) {
    return ObjectModel(
      id: id,
      name: _pick(languageCode, 'name', name),
      name2: _pick(languageCode, 'name2', name2),
      description: _pick(languageCode, 'description', description),
      cryptDescription: _pick(languageCode, 'cryptDescription', cryptDescription),
      imageUrl: imageUrl,
      imageUrl2: imageUrl2,
      extraImages: extraImages,
      galleryImages: galleryImages,
      location: _pickNullable(languageCode, 'location', location),
      direccion: _pickNullable(languageCode, 'direccion', direccion),
      celular: celular,
      openingHours: _pickNullable(languageCode, 'openingHours', openingHours),
      yearFounded: yearFounded,
      yearCompleted: yearCompleted,
      architecturalStyle:
          _pickNullable(languageCode, 'architecturalStyle', architecturalStyle),
      historicalNotes:
          _pickNullable(languageCode, 'historicalNotes', historicalNotes),
      entranceFee: _pickNullable(languageCode, 'entranceFee', entranceFee),
      tourAvailable: tourAvailable,
      category: _pickNullable(languageCode, 'category', category),
      relatedObjectId: relatedObjectId,
      translations: translations,
    );
  }

  factory ObjectModel.fromJson(Map<String, dynamic> json) {
    return ObjectModel(
      id: json['id'] ?? '',
      name: json['title'] ?? json['name'] ?? '',
      name2: json['title2'] ?? json['name2'] ?? '',
      description: json['description'] ?? '',
      cryptDescription: json['cryptDescription'] ?? '',
      imageUrl: json['imageUrl'] ?? json['image_url'] ?? '',
      imageUrl2: json['imageUrl2'] ?? json['image_url2'] ?? '',
      extraImages: List<String>.from(json['extraImages'] ?? json['extra_images'] ?? []),
      galleryImages: List<String>.from(json['galleryImages'] ?? []),
      location: json['location'],
      direccion: json['direccion'],
      celular: json['celular'],
      openingHours: json['openingHours'],
      yearFounded: json['yearFounded'],
      yearCompleted: json['yearCompleted'],
      architecturalStyle: json['architecturalStyle'],
      historicalNotes: json['historicalNotes'],
      entranceFee: json['entranceFee'],
      tourAvailable: json['tourAvailable'] ?? false,
      category: json['category'],
      relatedObjectId: json['relatedObjectId'],
      translations: _translationsFromJson(json),
    );
  }

  static Map<String, Map<String, String>> _translationsFromJson(
    Map<String, dynamic> json,
  ) {
    final stored = <String, Map<String, String>>{};
    final raw = json['translations'];
    if (raw is Map) {
      raw.forEach((locale, value) {
        if (value is Map) {
          stored[locale.toString()] = value.map(
            (key, text) => MapEntry(key.toString(), text?.toString() ?? ''),
          );
        }
      });
    }
    stored.putIfAbsent('es', () => {});
    stored['es']!.putIfAbsent('name', () => (json['title'] ?? json['name'] ?? '').toString());
    stored['es']!.putIfAbsent('name2', () => (json['title2'] ?? json['name2'] ?? '').toString());
    stored['es']!.putIfAbsent('description', () => (json['description'] ?? '').toString());
    stored['es']!.putIfAbsent('cryptDescription', () => (json['cryptDescription'] ?? '').toString());
    stored['es']!.putIfAbsent('location', () => (json['location'] ?? '').toString());
    stored['es']!.putIfAbsent('direccion', () => (json['direccion'] ?? '').toString());
    stored['es']!.putIfAbsent('openingHours', () => (json['openingHours'] ?? '').toString());
    stored['es']!.putIfAbsent('architecturalStyle', () => (json['architecturalStyle'] ?? '').toString());
    stored['es']!.putIfAbsent('historicalNotes', () => (json['historicalNotes'] ?? '').toString());
    stored['es']!.putIfAbsent('entranceFee', () => (json['entranceFee'] ?? '').toString());
    stored['es']!.putIfAbsent('category', () => (json['category'] ?? '').toString());
    return stored;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name2': name2,
      'description': description,
      'cryptDescription': cryptDescription,
      'imageUrl': imageUrl,
      'imageUrl2': imageUrl2,
      'extraImages': extraImages,
      'galleryImages': galleryImages,
      'location': location,
      'direccion': direccion,
      'celular': celular,
      'openingHours': openingHours,
      'yearFounded': yearFounded,
      'yearCompleted': yearCompleted,
      'architecturalStyle': architecturalStyle,
      'historicalNotes': historicalNotes,
      'entranceFee': entranceFee,
      'tourAvailable': tourAvailable,
      'category': category,
      'relatedObjectId': relatedObjectId,
    };
  }
}
