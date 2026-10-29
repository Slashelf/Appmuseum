import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda las claves fuera de SharedPreferences, que las deja en texto claro.
abstract class GuideSecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String? value);
}

/// Almacén en memoria. Lo usan las pruebas para no tocar el llavero del sistema.
class MemoryGuideSecretStore implements GuideSecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      values.remove(key);
    } else {
      values[key] = trimmed;
    }
  }
}

class SecureGuideSecretStore implements GuideSecretStore {
  final FlutterSecureStorage _storage;

  SecureGuideSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: trimmed);
    }
  }
}
