import 'package:flutter/material.dart';

import '../../models/object_model.dart';

class GuideRoutes {
  static const place = 'place';
  static const chat = 'chat';
}

/// Abre el lugar del beacon sustituyendo las fichas ya abiertas.
/// Si el chat está delante, no añade otra pantalla.
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
    if (route.settings.name == GuideRoutes.chat) {
      chatIsOpen = true;
      return true;
    }
    return false;
  });
  if (chatIsOpen) return;
  navigator.push(placeRoute(place));
}
