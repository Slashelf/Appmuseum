import '../models/object_model.dart';

enum LocalExhibitionQuestion { founded, images, visit }

/// Respuestas cortas de la exhibición del beacon. El año sale del texto escrito,
/// nunca del número yearFounded.
class LocalExhibitionAnswers {
  static final RegExp _year = RegExp(r'\b(1[4-9]\d{2}|20\d{2})\b');

  static String reply({
    required LocalExhibitionQuestion question,
    required ObjectModel? place,
    required String languageCode,
  }) {
    final language = _language(languageCode);
    if (place == null) return _noExhibition(language);
    final text = place.localized(language);
    final name = text.name.trim().isNotEmpty ? text.name.trim() : text.name2.trim();
    final shown = name.isEmpty ? _unnamed(language) : name;
    switch (question) {
      case LocalExhibitionQuestion.founded:
        return _founded(language, shown, text);
      case LocalExhibitionQuestion.images:
        return _images(language, shown, text.description);
      case LocalExhibitionQuestion.visit:
        return _visit(language, shown, text);
    }
  }

  static String onlyButtons(String languageCode) {
    switch (_language(languageCode)) {
      case 'en':
        return 'In local mode I can say when it was founded, what the images show, and how to visit.';
      case 'de':
        return 'Im lokalen Modus sage ich, wann es gegründet wurde, was die Bilder zeigen und wie man es besucht.';
      default:
        return 'En modo local puedo decir cuándo se fundó, qué muestran las imágenes y cómo visitarlo.';
    }
  }

  static String _language(String languageCode) {
    return languageCode == 'en' || languageCode == 'de' ? languageCode : 'es';
  }

  static String _noExhibition(String language) {
    switch (language) {
      case 'en':
        return 'Come close to an exhibition to use these answers.';
      case 'de':
        return 'Gehen Sie zu einer Ausstellung, um diese Antworten zu nutzen.';
      default:
        return 'Acércate a una exhibición para usar estas respuestas.';
    }
  }

  static String _unnamed(String language) {
    switch (language) {
      case 'en':
        return 'this exhibition';
      case 'de':
        return 'diese Ausstellung';
      default:
        return 'esta exhibición';
    }
  }

  static String _founded(String language, String name, ObjectModel text) {
    final sentence = _yearSentence(text);
    if (sentence == null) {
      switch (language) {
        case 'en':
          return 'This exhibition about $name does not give a year in its text.';
        case 'de':
          return 'Diese Ausstellung über $name nennt in ihrem Text kein Jahr.';
        default:
          return 'Esta exhibición sobre $name no trae un año en su texto.';
      }
    }
    switch (language) {
      case 'en':
        return 'This exhibition about $name says: $sentence';
      case 'de':
        return 'Diese Ausstellung über $name sagt: $sentence';
      default:
        return 'Esta exhibición sobre $name dice: $sentence';
    }
  }

  static String? _yearSentence(ObjectModel text) {
    for (final prose in [
      text.cryptDescription,
      text.description,
      text.historicalNotes ?? '',
    ]) {
      final sentence = _firstYearSentence(prose);
      if (sentence != null) return sentence;
    }
    return null;
  }

  static String? _firstYearSentence(String prose) {
    final trimmed = prose.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(RegExp(r'(?<=[.!?])\s+'));
    for (final part in parts) {
      final sentence = part.trim();
      if (sentence.isNotEmpty && _year.hasMatch(sentence)) return sentence;
    }
    return null;
  }

  static String _images(String language, String name, String description) {
    final shown = description.trim();
    if (shown.isEmpty) {
      switch (language) {
        case 'en':
          return 'This exhibition about $name does not describe the images.';
        case 'de':
          return 'Diese Ausstellung über $name beschreibt die Bilder nicht.';
        default:
          return 'Esta exhibición sobre $name no describe las imágenes.';
      }
    }
    switch (language) {
      case 'en':
        return 'The images in this exhibition about $name show: $shown';
      case 'de':
        return 'Die Bilder dieser Ausstellung über $name zeigen: $shown';
      default:
        return 'Las imágenes de esta exhibición sobre $name muestran: $shown';
    }
  }

  static String _visit(String language, String name, ObjectModel text) {
    var address = (text.direccion ?? '').trim();
    if (address.isEmpty) address = (text.location ?? '').trim();
    final hours = (text.openingHours ?? '').trim();
    if (address.isEmpty && hours.isEmpty) {
      switch (language) {
        case 'en':
          return 'The guide does not have the address or the hours for visiting the place of this exhibition about $name.';
        case 'de':
          return 'Die Führung hat weder die Adresse noch die Öffnungszeiten für den Besuch des Ortes dieser Ausstellung über $name.';
        default:
          return 'La guía no tiene la dirección ni el horario para visitar el lugar de esta exhibición sobre $name.';
      }
    }
    if (address.isNotEmpty && hours.isNotEmpty) {
      switch (language) {
        case 'en':
          return 'To visit the place of this exhibition about $name, the address is $address. Hours: $hours.';
        case 'de':
          return 'Um den Ort dieser Ausstellung über $name zu besuchen, lautet die Adresse $address. Öffnungszeiten: $hours.';
        default:
          return 'Para visitar el lugar de esta exhibición sobre $name, la dirección es $address. Horario: $hours.';
      }
    }
    if (address.isNotEmpty) {
      switch (language) {
        case 'en':
          return 'To visit the place of this exhibition about $name, the address is $address.';
        case 'de':
          return 'Um den Ort dieser Ausstellung über $name zu besuchen, lautet die Adresse $address.';
        default:
          return 'Para visitar el lugar de esta exhibición sobre $name, la dirección es $address.';
      }
    }
    switch (language) {
      case 'en':
        return 'To visit the place of this exhibition about $name, the hours are $hours.';
      case 'de':
        return 'Um den Ort dieser Ausstellung über $name zu besuchen, sind die Öffnungszeiten $hours.';
      default:
        return 'Para visitar el lugar de esta exhibición sobre $name, el horario es $hours.';
    }
  }
}
