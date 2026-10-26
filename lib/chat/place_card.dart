import '../models/object_model.dart';
import '../models/recommended_model.dart';

/// Ficha que puede ver la guía. Omite el año numérico y el teléfono de relleno.
class PlaceCard {
  static const placeholderPhone = '12345679';

  static String fromPlace(ObjectModel place, String languageCode) {
    final text = place.localized(languageCode);
    final name = text.name.trim().isNotEmpty ? text.name.trim() : text.name2.trim();
    return _lines(
      name: name,
      otherName: text.name2,
      description: text.description,
      complement: text.cryptDescription,
      hours: text.openingHours,
      address: _first(text.direccion, text.location),
      fee: text.entranceFee,
      style: text.architecturalStyle,
      notes: text.historicalNotes,
      phone: text.celular,
      category: text.category,
      tours: text.tourAvailable == true,
    );
  }

  static String fromRecommended(RecommendedModel item, String languageCode) {
    final text = item.localized(languageCode);
    return _lines(
      name: text.title,
      otherName: '',
      description: text.description,
      complement: '',
      hours: text.openingHours,
      address: _first(text.direccion, text.location),
      fee: text.entranceFee,
      style: text.architecturalStyle,
      notes: text.historicalNotes,
      phone: text.celular,
      category: text.category,
      tours: false,
    );
  }

  static String _first(String? preferred, String? fallback) {
    final first = preferred?.trim() ?? '';
    if (first.isNotEmpty) return first;
    return fallback?.trim() ?? '';
  }

  static String _lines({
    required String name,
    required String otherName,
    required String description,
    required String complement,
    required String? hours,
    required String address,
    required String? fee,
    required String? style,
    required String? notes,
    required String? phone,
    required String? category,
    required bool tours,
  }) {
    final lines = <String>[];
    void add(String label, String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return;
      lines.add('$label: $trimmed');
    }

    add('Exhibición', name);
    add('Lugar que representa', name);
    final alias = otherName.trim();
    if (alias.isNotEmpty && alias != name.trim()) add('Otro nombre', alias);
    add('Qué muestran las imágenes o piezas', description);
    add('Iglesia o cripta', complement);
    add('Horario', hours);
    add('Dirección', address);
    add('Precio', fee);
    add('Estilo', style);
    add('Notas', notes);
    add('Categoría', category);
    if (tours) add('Actividades', 'Visitas guiadas');
    if (!_isPlaceholderPhone(phone)) add('Contacto', phone);
    return lines.join('\n');
  }

  static bool _isPlaceholderPhone(String? phone) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty || digits == placeholderPhone;
  }
}
