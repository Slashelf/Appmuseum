class ObjectCarousel {
  final String title;
  final List<String> description;
  final List<String> images;
  final Map<String, List<String>> paragraphsByLocale;
  final Map<String, String> titlesByLocale;

  ObjectCarousel({
    required this.title,
    required this.description,
    required this.images,
    this.paragraphsByLocale = const {},
    this.titlesByLocale = const {},
  });

  factory ObjectCarousel.fromJson(Map<String, dynamic> json) {
    final imagesField = json['images'];
    final images = imagesField is List
        ? List<String>.from(imagesField)
        : imagesField is String && imagesField.trim().isNotEmpty
            ? [imagesField]
            : <String>[];
    return ObjectCarousel(
      title: json['title'] ?? '',
      description: List<String>.from(json['description'] ?? []),
      images: images,
    );
  }

  ObjectCarousel localized(String languageCode) {
    final paragraphs = paragraphsByLocale[languageCode] ??
        paragraphsByLocale['es'] ??
        description;
    final localizedTitle =
        titlesByLocale[languageCode] ?? titlesByLocale['es'] ?? title;
    return ObjectCarousel(
      title: localizedTitle,
      description: paragraphs,
      images: images,
      paragraphsByLocale: paragraphsByLocale,
      titlesByLocale: titlesByLocale,
    );
  }
}
