class RecommendedModel {
  final String title;
  final String imageUrl;
  final String location;
  final String description;
  final double latitude;
  final double longitude;
  final double altitude;
  final String openingHours;
  final String? sourceId;
  final String? celular;
  final String? direccion;
  final int? yearFounded;
  final int? yearCompleted;
  final String? architecturalStyle;
  final String? historicalNotes;
  final String? entranceFee;
  final String? category;
  final List<String> extraImages;
  final Map<String, Map<String, String>> translations;

  RecommendedModel({
    required this.title,
    required this.imageUrl,
    required this.location,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.openingHours,
    this.sourceId,
    this.celular,
    this.direccion,
    this.yearFounded,
    this.yearCompleted,
    this.architecturalStyle,
    this.historicalNotes,
    this.entranceFee,
    this.category,
    this.extraImages = const [],
    this.translations = const {},
  });

  String _pick(String languageCode, String key, String fallback) {
    final current = translations[languageCode]?[key];
    if (current != null && current.trim().isNotEmpty) return current;
    final spanish = translations['es']?[key];
    if (spanish != null && spanish.trim().isNotEmpty) return spanish;
    return fallback;
  }

  RecommendedModel localized(String languageCode) {
    return RecommendedModel(
      title: _pick(languageCode, 'title', title),
      imageUrl: imageUrl,
      location: _pick(languageCode, 'location', location),
      description: _pick(languageCode, 'description', description),
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      openingHours: _pick(languageCode, 'openingHours', openingHours),
      sourceId: sourceId,
      celular: celular,
      direccion: direccion,
      yearFounded: yearFounded,
      yearCompleted: yearCompleted,
      architecturalStyle: architecturalStyle,
      historicalNotes: historicalNotes,
      entranceFee: entranceFee,
      category: category,
      extraImages: extraImages,
      translations: translations,
    );
  }

  factory RecommendedModel.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'];
    double readDouble(String key) {
      final direct = json[key];
      final nested = coords is Map ? coords[key] : null;
      final value = direct ?? nested ?? 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    final translations = <String, Map<String, String>>{};
    final raw = json['translations'];
    if (raw is Map) {
      raw.forEach((locale, value) {
        if (value is Map) {
          translations[locale.toString()] = value.map(
            (key, text) => MapEntry(key.toString(), text?.toString() ?? ''),
          );
        }
      });
    }
    translations.putIfAbsent('es', () => {});
    translations['es']!.putIfAbsent('title', () => (json['title'] ?? '').toString());
    translations['es']!.putIfAbsent('location', () => (json['location'] ?? '').toString());
    translations['es']!.putIfAbsent('description', () => (json['description'] ?? '').toString());
    translations['es']!.putIfAbsent(
      'openingHours',
      () => (json['openingHours'] ?? '').toString(),
    );

    return RecommendedModel(
      title: json['title'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      location: json['location'] ?? '',
      description: json['description'] ?? '',
      latitude: readDouble('latitude'),
      longitude: readDouble('longitude'),
      altitude: readDouble('altitude'),
      openingHours: json['openingHours'] ?? '',
      sourceId: json['id']?.toString(),
      celular: (json['celular'] ?? json['celuldar'])?.toString(),
      direccion: json['direccion']?.toString(),
      yearFounded: json['yearFounded'] is int ? json['yearFounded'] as int : null,
      yearCompleted: json['yearCompleted'] is int ? json['yearCompleted'] as int : null,
      architecturalStyle: json['architecturalStyle']?.toString(),
      historicalNotes: json['historicalNotes']?.toString(),
      entranceFee: json['entranceFee']?.toString(),
      category: json['category']?.toString(),
      extraImages: List<String>.from(json['extraImages'] ?? const []),
      translations: translations,
    );
  }
}
