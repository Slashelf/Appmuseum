import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'chat_voice.dart';
import 'eleven_labs_speech.dart';

class NarrationFetch {
  final int status;
  final Uint8List bytes;

  const NarrationFetch({required this.status, required this.bytes});
}

/// Lee una frase con ElevenLabs y, si falla, con la voz del teléfono.
///
/// No muestra errores. La frase se pide en cuanto existe; el audio de esa
/// frase suena al terminar su descarga, mientras el modelo puede seguir.
class GuideNarrator {
  GuideNarrator({
    required this.fallback,
    this.fetch,
    this.onBytes,
  });

  final ChatSpeaker fallback;
  final Future<NarrationFetch> Function(String text, String apiKey, String voiceId)? fetch;
  final void Function(Uint8List bytes)? onBytes;

  final List<Future<NarrationFetch>> _pending = [];
  bool _busy = false;
  bool _stopped = false;
  AudioPlayer? _player;
  void Function()? onIdle;

  bool get busy => _busy || _pending.isNotEmpty;

  void enqueue(
    String text, {
    required String languageCode,
    required String Function() apiKey,
    required String Function() voiceId,
  }) {
    final spoken = text.trim();
    if (spoken.isEmpty || _stopped) return;
    final secret = apiKey().trim();
    final voice = voiceId().trim().isEmpty ? ElevenLabsSpeech.voiceId : voiceId().trim();
    if (secret.isEmpty) {
      _pending.add(Future.value(NarrationFetch(status: 0, bytes: _empty)));
    } else {
      _pending.add((fetch ?? fetchFromNetwork)(spoken, secret, voice));
    }
    _jobs.add(_NarrationJob(spoken, languageCode, secret.isEmpty));
    _pump();
  }

  final List<_NarrationJob> _jobs = [];

  Future<void> stop() async {
    _stopped = true;
    _pending.clear();
    _jobs.clear();
    _busy = false;
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await fallback.stop();
    } catch (_) {}
    _stopped = false;
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    while (_jobs.isNotEmpty && _pending.isNotEmpty && !_stopped) {
      final job = _jobs.removeAt(0);
      NarrationFetch result;
      try {
        result = await _pending.removeAt(0);
      } catch (_) {
        result = NarrationFetch(status: 0, bytes: _empty);
      }
      if (_stopped) break;
      await _play(job, result);
    }
    _busy = false;
    if (!_stopped && _jobs.isEmpty) onIdle?.call();
  }

  Future<void> _play(_NarrationJob job, NarrationFetch result) async {
    final usable = !job.deviceOnly &&
        result.status == 200 &&
        result.bytes.isNotEmpty;
    if (usable) {
      try {
        if (onBytes != null) {
          onBytes!(result.bytes);
          return;
        }
        final player = _player ??= AudioPlayer();
        await player.setAudioSource(_Mp3Bytes(result.bytes));
        await player.play();
        return;
      } catch (_) {}
    }
    final done = Completer<void>();
    try {
      await fallback.speak(
        text: job.text,
        languageCode: job.languageCode,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 40));
    } catch (_) {
      if (!done.isCompleted) done.complete();
    }
  }

  static Future<NarrationFetch> fetchFromNetwork(
    String text,
    String apiKey,
    String voiceId,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(ElevenLabsSpeech.streamUri(voiceId));
      ElevenLabsSpeech.headers(apiKey).forEach(request.headers.set);
      request.write(jsonEncode(ElevenLabsSpeech.body(text)));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return NarrationFetch(status: response.statusCode, bytes: _empty);
      }
      final data = await response.fold<List<int>>(<int>[], (bytes, chunk) {
        bytes.addAll(chunk);
        return bytes;
      });
      return NarrationFetch(status: 200, bytes: Uint8List.fromList(data));
    } finally {
      client.close(force: true);
    }
  }
}

final _empty = Uint8List(0);

class _NarrationJob {
  final String text;
  final String languageCode;
  final bool deviceOnly;

  const _NarrationJob(this.text, this.languageCode, this.deviceOnly);
}

class _Mp3Bytes extends StreamAudioSource {
  final Uint8List bytes;

  _Mp3Bytes(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream<List<int>>.value(bytes.sublist(from, to)),
      contentType: 'audio/mpeg',
    );
  }
}
