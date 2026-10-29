import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'remote_guide_answer_service.dart';

/// Elige una voz premade. No guarda un id escrito a mano.
abstract class NarratorVoiceSource {
  Future<String?> pick(String apiKey);

  /// Conserva [currentId] si ya es válido. Si no, elige una voz.
  Future<String?> resolve(String apiKey, String currentId) {
    if (currentId.trim().isNotEmpty) return Future.value(currentId.trim());
    return pick(apiKey);
  }
}

/// Narrador premade en español, cálido si el listado lo dice.
class SpanishNarrator {
  static String? choose(Iterable<dynamic> voices) {
    String? bestId;
    var bestScore = 0;
    var bestName = '';
    for (final raw in voices) {
      if (raw is! Map) continue;
      final voice = Map<String, dynamic>.from(raw);
      final id = voice['voice_id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final category = (voice['category']?.toString() ?? '').toLowerCase();
      if (category != 'premade') continue;
      if (!_speaksSpanish(voice)) continue;
      final score = _warmth(voice);
      final name = (voice['name']?.toString() ?? '').toLowerCase();
      final better = bestId == null ||
          score > bestScore ||
          (score == bestScore && name.compareTo(bestName) < 0) ||
          (score == bestScore && name == bestName && id.compareTo(bestId) < 0);
      if (!better) continue;
      bestId = id;
      bestScore = score;
      bestName = name;
    }
    return bestId;
  }

  static bool _speaksSpanish(Map<String, dynamic> voice) {
    final verified = voice['verified_languages'];
    if (verified is List) {
      for (final item in verified) {
        if (item is! Map) continue;
        final language = item['language']?.toString().toLowerCase() ?? '';
        if (language == 'es' || language.startsWith('es-') || language.startsWith('es_')) {
          return true;
        }
      }
    }
    final labels = voice['labels'];
    if (labels is! Map) return false;
    final language = labels['language']?.toString().toLowerCase() ?? '';
    if (language == 'es' || language.startsWith('es-') || language.startsWith('es_')) {
      return true;
    }
    final locale = labels['locale']?.toString().toLowerCase() ?? '';
    if (locale == 'es' || locale.startsWith('es-') || locale.startsWith('es_')) {
      return true;
    }
    final accent = _plain(labels['accent']?.toString() ?? '');
    const hints = [
      'spanish',
      'espanol',
      'castellano',
      'castilian',
      'peninsular',
      'latin',
    ];
    for (final hint in hints) {
      if (accent.contains(hint)) return true;
    }
    return false;
  }

  static int _warmth(Map<String, dynamic> voice) {
    final labels = voice['labels'];
    final parts = <String>[
      voice['description']?.toString() ?? '',
    ];
    var gender = '';
    if (labels is Map) {
      parts.add(labels['description']?.toString() ?? '');
      parts.add(labels['use_case']?.toString() ?? '');
      gender = labels['gender']?.toString().toLowerCase() ?? '';
    }
    final text = _plain(parts.join(' '));
    var score = 1;
    if (text.contains('narrat')) score += 8;
    if (text.contains('warm') || text.contains('calid')) score += 4;
    if (gender == 'male' || gender == 'masculine' || gender == 'masculino') {
      score += 1;
    }
    return score;
  }

  static String _plain(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }
}

/// Pide GET /v1/voices con la clave de Ajustes. Si falla, no elige un id.
class SpanishNarratorLookup implements NarratorVoiceSource {
  const SpanishNarratorLookup({this.load});

  static final voicesUri = Uri.parse('https://api.x.ai/v1/tts/voices');
  static const lookupBudget = Duration(seconds: 8);

  /// Doble de prueba. Si es null, se usa el listado oficial.
  final Future<List<Map<String, dynamic>>> Function(String apiKey)? load;

  @override
  Future<String?> pick(String apiKey) => resolve(apiKey, '');

  @override
  Future<String?> resolve(String apiKey, String currentId) async {
    if (currentId.trim() == 'leo') return 'leo';
    return 'ara';
  }

  static Future<List<Map<String, dynamic>>> download(String apiKey) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(voicesUri).timeout(lookupBudget);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${apiKey.trim()}');
      final response = await request.close().timeout(lookupBudget);
      final raw = await response.transform(utf8.decoder).join().timeout(lookupBudget);
      if (response.statusCode != 200) {
        final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
        final clipped = compact.length <= 180 ? compact : compact.substring(0, 180);
        debugPrint(
          'Voces: ${response.statusCode} ${DeepSeekLog.safe(clipped, apiKey)}',
        );
        return const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['voices'] is! List) return const [];
      return [
        for (final voice in decoded['voices'] as List)
          if (voice is Map) Map<String, dynamic>.from(voice),
      ];
    } finally {
      client.close(force: true);
    }
  }
}
