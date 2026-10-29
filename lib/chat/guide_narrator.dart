import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'chat_voice.dart';
import 'xai_speech.dart';
import 'remote_guide_answer_service.dart';
import 'speech_route.dart';

/// Reproductor de un clip. Las pruebas inyectan un doble y no abren AudioPlayer.
abstract class ClipPlayback {
  Future<void> load(StreamAudioSource source);

  Future<void> play();

  Future<void> stop();

  Future<void> close();
}

class NarrationRequest {
  final String text;
  final String apiKey;
  final String voiceId;
  final String languageCode;
  final String? previousText;

  const NarrationRequest({
    required this.text,
    required this.apiKey,
    required this.voiceId,
    required this.languageCode,
    this.previousText,
  });
}

class NarrationFetch {
  final int status;
  final Uint8List bytes;
  final String detail;
  final Stream<List<int>>? audio;

  /// Tiempo que queda del tope para oír el primer fragmento.
  final Duration? audioBudget;
  final Future<void> Function()? cancel;

  NarrationFetch({
    required this.status,
    Uint8List? bytes,
    this.detail = '',
    this.audio,
    this.audioBudget,
    this.cancel,
  }) : bytes = bytes ?? _empty;
}

/// Lee una frase con la voz de Grok y, si falla, con la voz del teléfono.
///
/// El audio de la frase empieza con el primer fragmento. Si en unos 8
/// segundos no llega audio útil, habla el teléfono. La frase anterior de
/// la misma respuesta viaja como previous_text.
class GuideNarrator {
  GuideNarrator({
    required this.fallback,
    this.fetch,
    this.onBytes,
    this.onUsefulAudio,
    Duration? usefulAudioWait,
    this.openPlayback,
    this.prepareRoute,
  }) : usefulAudioWait = usefulAudioWait ?? usefulAudioLimit;

  static const usefulAudioLimit = Duration(seconds: 8);

  final ChatSpeaker fallback;
  final Future<NarrationFetch> Function(NarrationRequest request)? fetch;
  final void Function(Uint8List bytes)? onBytes;
  final void Function(Uint8List bytes)? onUsefulAudio;
  final Duration usefulAudioWait;
  final ClipPlayback Function()? openPlayback;
  final Future<void> Function()? prepareRoute;

  final List<Future<NarrationFetch>> _pending = [];
  final List<HttpClient> _clients = [];
  bool _busy = false;
  bool _stopped = false;
  bool _closed = false;
  int _generation = 0;
  String? _previousInReply;
  ClipPlayback? _playback;

  /// Cierto cuando [dispose] soltó el reproductor.
  bool get playerReleased => _closed && _playback == null;
  void Function()? onIdle;
  void Function(String reason)? onPhoneVoice;
  void Function()? onRemoteVoice;

  /// Motivo de la última caída al teléfono. Vacío si la voz de Grok sonó.
  String? lastPhoneReason;

  bool get busy => _busy || _pending.isNotEmpty;

  /// La siguiente frase es de otra respuesta: no arrastra previous_text.
  void beginReply() {
    _previousInReply = null;
  }

  void enqueue(
    String text, {
    required String languageCode,
    required String Function() apiKey,
    required String Function() voiceId,
  }) {
    final spoken = text.trim();
    if (spoken.isEmpty || _stopped || _closed) return;
    final secret = apiKey().trim();
    final voice = voiceId().trim();
    final request = NarrationRequest(
      text: spoken,
      apiKey: secret,
      voiceId: voice,
      languageCode: languageCode,
      previousText: _previousInReply,
    );
    _previousInReply = spoken;
    final generation = _generation;
    if (secret.isEmpty || voice.isEmpty) {
      _pending.add(Future.value(NarrationFetch(status: 0)));
    } else {
      _pending.add(_load(request, generation));
    }
    _jobs.add(_NarrationJob(request, secret.isEmpty || voice.isEmpty));
    _pump();
  }

  final List<_NarrationJob> _jobs = [];

  /// Suelta el reproductor. Después de esto una frase nueva no suena.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await stop();
    final playback = _playback;
    _playback = null;
    if (playback == null) return;
    try {
      await playback.close();
    } catch (_) {}
  }

  Future<void> stop() async {
    _generation++;
    _previousInReply = null;
    _stopped = true;
    _pending.clear();
    _jobs.clear();
    _busy = false;
    final live = List<HttpClient>.of(_clients);
    _clients.clear();
    for (final client in live) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    try {
      await _playback?.stop();
    } catch (_) {}
    try {
      await fallback.stop();
    } catch (_) {}
    _stopped = false;
  }

  Future<NarrationFetch> _load(NarrationRequest request, int generation) async {
    try {
      final result = await (fetch ?? _fetchLive)(request);
      if (generation != _generation) {
        await result.cancel?.call();
        return NarrationFetch(status: 0, detail: 'cancelado');
      }
      return result;
    } catch (error) {
      return NarrationFetch(
        status: 0,
        detail: DeepSeekLog.safe('$error', request.apiKey),
      );
    }
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    final run = _generation;
    while (_jobs.isNotEmpty && _pending.isNotEmpty && run == _generation && !_closed) {
      final job = _jobs.removeAt(0);
      final pending = _pending.removeAt(0);
      NarrationFetch result;
      try {
        result = await pending;
      } catch (error) {
        result = NarrationFetch(
          status: 0,
          detail: DeepSeekLog.safe('$error', job.request.apiKey),
        );
      }
      if (run != _generation || _stopped || _closed) {
        await result.cancel?.call();
        break;
      }
      await _play(job, result);
    }
    _busy = false;
    if (run == _generation && !_closed && _jobs.isEmpty) onIdle?.call();
  }

  Future<void> _play(_NarrationJob job, NarrationFetch result) async {
    if (_stopped || _closed) {
      await result.cancel?.call();
      return;
    }
    if (!job.deviceOnly && result.status == 200) {
      if (result.bytes.isNotEmpty && result.audio == null) {
        final played = await _playBytes(result.bytes);
        if (played || _stopped || _closed) return;
      } else if (result.audio != null) {
        final played = await _playStream(result);
        if (played || _stopped || _closed) return;
        _notePhone(
          result.detail.isEmpty ? '200 sin audio' : '200 ${result.detail}',
          job.request.apiKey,
        );
        await _speakPhone(job);
        return;
      }
    }
    if (!job.deviceOnly) {
      final reason = result.detail.isEmpty
          ? (result.status == 200 ? '200 sin audio' : '${result.status}')
          : '${result.status} ${result.detail}';
      _notePhone(reason, job.request.apiKey);
    }
    await _speakPhone(job);
  }

  void _notePhone(String reason, String secret) {
    final clean = DeepSeekLog.safe(reason.trim(), secret);
    if (clean.isEmpty) return;
    lastPhoneReason = clean;
    debugPrint('Voz: $clean');
    onPhoneVoice?.call(clean);
  }

  Future<void> _prepareRoute() async {
    try {
      await (prepareRoute ?? SpeechRoute.prepare)();
    } catch (_) {}
  }

  ClipPlayback _openClip() {
    final opener = openPlayback;
    if (opener != null) return opener();
    return _JustClipPlayback();
  }

  Future<bool> _playBytes(Uint8List bytes) async {
    if (_closed) return false;
    if (onUsefulAudio != null) {
      onUsefulAudio!(bytes);
      _heardRemote();
      return true;
    }
    if (onBytes != null) {
      onBytes!(bytes);
      _heardRemote();
      return true;
    }
    try {
      await _prepareRoute();
      if (_closed || _stopped) return false;
      final playback = _playback ??= _openClip();
      await playback.load(_Mp3Bytes(bytes));
      if (_closed) return false;
      _heardRemote();
      await playback.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playStream(NarrationFetch result) async {
    final audio = result.audio;
    if (audio == null) return false;
    final growth = _GrowingMp3();
    final ready = Completer<Uint8List?>();
    final buffered = BytesBuilder(copy: false);
    late final StreamSubscription<List<int>> sub;
    Timer? timer;
    sub = audio.listen(
      (chunk) {
        if (chunk.isEmpty) return;
        buffered.add(chunk);
        growth.add(chunk);
        if (!ready.isCompleted) {
          timer?.cancel();
          ready.complete(Uint8List.fromList(chunk));
        }
      },
      onError: (Object _) {
        timer?.cancel();
        growth.finish();
        if (!ready.isCompleted) {
          ready.complete(buffered.isEmpty ? null : buffered.toBytes());
        }
      },
      onDone: () {
        timer?.cancel();
        growth.finish();
        if (!ready.isCompleted) {
          ready.complete(buffered.isEmpty ? null : buffered.toBytes());
        }
      },
    );
    timer = Timer(result.audioBudget ?? usefulAudioWait, () {
      if (!ready.isCompleted) ready.complete(null);
    });
    final first = await ready.future;
    timer.cancel();
    if (_stopped || _closed) {
      await _closeStream(sub, result, growth);
      return true;
    }
    if (first == null || first.isEmpty) {
      await _closeStream(sub, result, growth);
      return false;
    }
    if (onUsefulAudio != null) {
      onUsefulAudio!(first);
      _heardRemote();
      await _closeStream(sub, result, growth);
      return true;
    }
    if (onBytes != null) {
      onBytes!(buffered.toBytes());
      _heardRemote();
      await _closeStream(sub, result, growth);
      return true;
    }
    var started = false;
    try {
      await _prepareRoute();
      if (_closed || _stopped) return false;
      final playback = _playback ??= _openClip();
      await playback.load(growth);
      if (_closed) return started;
      started = true;
      _heardRemote();
      await playback.play();
      return true;
    } catch (_) {
      return started;
    } finally {
      await _closeStream(sub, result, growth);
    }
  }

  void _heardRemote() {
    lastPhoneReason = null;
    onRemoteVoice?.call();
  }

  Future<void> _closeStream(
    StreamSubscription<List<int>> sub,
    NarrationFetch result,
    _GrowingMp3 growth,
  ) async {
    try {
      await sub.cancel();
    } catch (_) {}
    growth.finish();
    try {
      await result.cancel?.call();
    } catch (_) {}
  }

  Future<void> _speakPhone(_NarrationJob job) async {
    if (_stopped || _closed) return;
    final done = Completer<void>();
    try {
      await fallback.speak(
        text: job.request.text,
        languageCode: job.request.languageCode,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 40));
    } catch (_) {
      if (!done.isCompleted) done.complete();
    }
  }

  Future<NarrationFetch> _fetchLive(NarrationRequest request) async {
    final client = HttpClient();
    _clients.add(client);

    try {
      final http = await client
          .postUrl(XaiSpeech.endpoint)
          .timeout(const Duration(seconds: 20));
      XaiSpeech.headers(request.apiKey).forEach(http.headers.set);
      http.write(
        jsonEncode(
          XaiSpeech.body(
            request.text,
            voiceId: request.voiceId,
            languageCode: request.languageCode,
          ),
        ),
      );
      final response = await http.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        var detail = '';
        try {
          final raw = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
          detail = _clip(raw, request.apiKey);
        } catch (error) {
          detail = DeepSeekLog.safe('$error', request.apiKey);
        }
        return NarrationFetch(status: response.statusCode, detail: detail);
      }
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(const Duration(seconds: 20));
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        return NarrationFetch(status: 200, detail: '200 sin audio');
      }
      return NarrationFetch(status: 200, bytes: bytes);
    } catch (error) {
      return NarrationFetch(
        status: 0,
        detail: DeepSeekLog.safe('$error', request.apiKey),
      );
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  static String _clip(String raw, String secret) {
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final clipped = compact.length <= 180 ? compact : compact.substring(0, 180);
    return DeepSeekLog.safe(clipped, secret);
  }
}

final _empty = Uint8List(0);

class _NarrationJob {
  final NarrationRequest request;
  final bool deviceOnly;

  const _NarrationJob(this.request, this.deviceOnly);
}

class _JustClipPlayback implements ClipPlayback {
  _JustClipPlayback() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> load(StreamAudioSource source) async {
    await _player.setAudioSource(source);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> close() => _player.dispose();
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

/// MP3 que crece mientras ElevenLabs sigue enviando fragmentos.
class _GrowingMp3 extends StreamAudioSource {
  final List<int> _data = [];
  final List<Completer<void>> _waiters = [];
  bool _finished = false;

  void add(List<int> chunk) {
    if (_finished || chunk.isEmpty) return;
    _data.addAll(chunk);
    _wake();
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _wake();
  }

  void _wake() {
    for (final waiter in List<Completer<void>>.of(_waiters)) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final total = _finished ? _data.length : null;
    final until = end ?? total;
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: until == null ? null : until - from,
      offset: from,
      stream: _read(from, end),
      contentType: 'audio/mpeg',
    );
  }

  Stream<List<int>> _read(int from, int? end) async* {
    var cursor = from;
    while (true) {
      final limit = end ?? (_finished ? _data.length : null);
      if (cursor < _data.length) {
        var stop = _data.length;
        if (limit != null && limit < stop) stop = limit;
        if (stop > cursor) {
          yield Uint8List.fromList(_data.sublist(cursor, stop));
          cursor = stop;
          continue;
        }
      }
      if (limit != null && cursor >= limit) break;
      if (_finished && cursor >= _data.length) break;
      final waiter = Completer<void>();
      _waiters.add(waiter);
      if (!waiter.isCompleted && (cursor < _data.length || _finished)) {
        waiter.complete();
      }
      await waiter.future;
      _waiters.remove(waiter);
    }
  }
}
