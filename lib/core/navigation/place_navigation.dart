import 'package:flutter/material.dart';

import '../../models/object_model.dart';

class GuideRoutes {
  static const place = 'place';
  static const chat = 'chat';
  static const talk = 'talk';
}

/// Abre el lugar del beacon sustituyendo las fichas ya abiertas.
/// Si el chat o el modo hablar están delante, no añade otra pantalla.
void openPlaceFromBeacon(
  BuildContext context,
  ObjectModel place, {
  required Route<void> Function(ObjectModel place) placeRoute,
}) {
  if (!context.mounted) return;
  final navigator = Navigator.of(context);
  var chatIsOpen = false;
  navigator.popUntil((route) {
    if (route.isFirst) return true;
    final name = route.settings.name;
    if (name == GuideRoutes.chat || name == GuideRoutes.talk) {
      chatIsOpen = true;
      return true;
    }
    return false;
  });
  if (chatIsOpen) return;
  navigator.push(placeRoute(place));
}
