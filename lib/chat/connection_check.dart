import 'dart:convert';
import 'dart:io';

import 'remote_guide_answer_service.dart';

/// Resultado de “Probar conexión” o “Probar voz”. No incluye la clave.
class ConnectionReport {
  final bool ok;
  final int? status;
  final String detail;

  const ConnectionReport({
    required this.ok,
    this.status,
    this.detail = '',
  });

  String get message {
    if (ok) return '';
    final code = status == null || status == 0 ? '' : '$status ';
    return '$code$detail'.trim();
  }
}

/// Comprueba la clave sin redactar una respuesta. Las pruebas ponen un doble.
abstract class ConnectionChecker {
  Future<ConnectionReport> deepSeek(String apiKey);

  Future<ConnectionReport> elevenLabs(String apiKey);
}

class HttpConnectionChecker implements ConnectionChecker {
  static const models = 'https://api.x.ai/v1/models';

  @override
  Future<ConnectionReport> deepSeek(String apiKey) => _probe(apiKey);

  @override
  Future<ConnectionReport> elevenLabs(String apiKey) => _probe(apiKey);

  Future<ConnectionReport> _probe(String apiKey) {
    return _get(
      Uri.parse(models),
      apiKey,
      (request, key) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      },
    );
  }

  Future<ConnectionReport> _get(
    Uri url,
    String apiKey,
    void Function(HttpClientRequest request, String key) authorize,
  ) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const ConnectionReport(ok: false);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(url).timeout(const Duration(seconds: 12));
      authorize(request, key);
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return ConnectionReport(ok: true, status: 200);
      }
      final safe = DeepSeekLog.safe(body, key);
      final clip = safe.length > 180 ? safe.substring(0, 180) : safe;
      return ConnectionReport(
        ok: false,
        status: response.statusCode,
        detail: clip.trim(),
      );
    } catch (error) {
      return ConnectionReport(
        ok: false,
        detail: DeepSeekLog.safe('$error', key),
      );
    } finally {
      client.close(force: true);
    }
  }
}
