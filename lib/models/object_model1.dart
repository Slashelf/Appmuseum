class ObjectModell {
  final String id;
  final String title; // antes era name
  final String description;
  final String imageUrl;
  final List<String> extraImages;
  final String location;
  final String? direccion;
  final String? celular;
  final String openingHours;
  final int? yearFounded;
  final int? yearCompleted;
  final String? architecturalStyle;
  final String? historicalNotes;
  final String? entranceFee;
  final bool tourAvailable;
  final String? category;
  final String? relatedObjectId;

  ObjectModell({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.extraImages,
    required this.location,
    this.direccion,
    this.celular,
    required this.openingHours,
    this.yearFounded,
    this.yearCompleted,
    this.architecturalStyle,
    this.historicalNotes,
    this.entranceFee,
    required this.tourAvailable,
    this.category,
    this.relatedObjectId,
  });

  factory ObjectModell.fromJson(Map<String, dynamic> json) {
    return ObjectModell(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      imageUrl: json['imageUrl'],
      extraImages: List<String>.from(json['extraImages'] ?? []),
      location: json['location'],
      direccion: json['direccion'],
      celular: json['celular'],
      openingHours: json['openingHours'] ?? "",
      yearFounded: json['yearFounded'],
      yearCompleted: json['yearCompleted'],
      architecturalStyle: json['architecturalStyle'],
      historicalNotes: json['historicalNotes'],
      entranceFee: json['entranceFee'],
      tourAvailable: json['tourAvailable'] ?? false,
      category: json['category'],
      relatedObjectId: json['relatedObjectId'],
    );
  }
}
