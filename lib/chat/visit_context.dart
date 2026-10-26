import 'package:flutter/foundation.dart';

import '../models/object_model.dart';

/// Lugar detectado por el beacon. No abre pantallas ni borra el chat.
class VisitContext extends ChangeNotifier {
  ObjectModel? _place;

  ObjectModel? get place => _place;

  void updatePlace(ObjectModel? place) {
    if (_place?.id == place?.id) return;
    _place = place;
    notifyListeners();
  }
}
