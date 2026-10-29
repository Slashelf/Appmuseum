import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';

import 'chat_faq.dart';
import 'remote_guide_answer_service.dart';

/// Aviso ya interpretado de un evento del agente de voz. No abre la red.
class XaiVoiceNotice {
  final XaiVoiceNoticeKind kind;
  final String text;
  final bool replace;
  final bool ended;
  final Uint8List? audio;
  final XaiVoiceFailure? failure;

  const XaiVoiceNotice._({
    required this.kind,
    this.text = '',
    this.replace = false,
    this.ended = false,
    this.audio,
    this.failure,
  });

  const XaiVoiceNotice.ignore() : this._(kind: XaiVoiceNoticeKind.ignore);

  const XaiVoiceNotice.ready() : this._(kind: XaiVoiceNoticeKind.ready);

  const XaiVoiceNotice.visitorStarted()
      : this._(kind: XaiVoiceNoticeKind.visitorStarted);

  const XaiVoiceNotice.visitorStopped()
      : this._(kind: XaiVoiceNoticeKind.visitorStopped);

  const XaiVoiceNotice.visitorText(String text, {required bool replace, required bool ended})
      : this._(
          kind: XaiVoiceNoticeKind.visitorText,
          text: text,
          replace: replace,
          ended: ended,
        );

  const XaiVoiceNotice.guideStarted() : this._(kind: XaiVoiceNoticeKind.guideStarted);

  const XaiVoiceNotice.guideText(String text, {required bool replace})
      : this._(kind: XaiVoiceNoticeKind.guideText, text: text, replace: replace);

  const XaiVoiceNotice.guideAudio(Uint8List audio)
      : this._(kind: XaiVoiceNoticeKind.guideAudio, audio: audio);

  const XaiVoiceNotice.guideDone() : this._(kind: XaiVoiceNoticeKind.guideDone);

  const XaiVoiceNotice.failed(XaiVoiceFailure failure)
      : this._(kind: XaiVoiceNoticeKind.failed, failure: failure);
}

enum XaiVoiceNoticeKind {
  ignore,
  ready,
  visitorStarted,
  visitorStopped,
  visitorText,
  guideStarted,
  guideText,
  guideAudio,
  guideDone,
  failed,
}

/// Fallo de la voz. [offline] conserva el aviso de sin internet y no guarda respuesta.
class XaiVoiceFailure {
  final int? status;
  final String detail;
  final bool offline;
  final bool microphone;

  const XaiVoiceFailure({
    this.status,
    this.detail = '',
    this.offline = false,
    this.microphone = false,
  });

  static XaiVoiceFailure from(Object error, String secret) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is TlsException) {
      return const XaiVoiceFailure(offline: true);
    }
    final raw = DeepSeekLog.safe('$error', secret);
    return XaiVoiceFailure(status: XaiRealtime.statusOf(raw), detail: raw);
  }
}

/// Mensajes del agente de voz. Se pueden armar y leer sin abrir un socket.
class XaiRealtime {
  static const model = 'grok-voice-latest';
  static const sampleRate = 24000;

  static final Uri endpoint = Uri.parse('wss://api.x.ai/v1/realtime?model=$model');

  static String languageHint(String languageCode) {
    final code = languageCode.trim().toLowerCase();
    if (code.startsWith('en')) return 'en';
    if (code.startsWith('de')) return 'de';
    if (code.startsWith('pt')) return 'pt-BR';
    return 'es-MX';
  }

  static String voiceId(String stored) => stored.trim() == 'leo' ? 'leo' : 'ara';

  /// La sesión de voz lleva las mismas respuestas fijas que el chat escrito.
  static String _sessionInstructions(String instructions) {
    final text = instructions.trim();
    if (text.contains(ChatFaq.jokeOwes)) return text;
    return '$text\n${ChatFaq.voiceSessionRules}';
  }

  static Map<String, Object?> sessionUpdate({
    required String instructions,
    required String voice,
    required String languageCode,
  }) {
    return {
      'type': 'session.update',
      'session': {
        'voice': voiceId(voice),
        'instructions': _sessionInstructions(instructions),
        'turn_detection': {'type': 'server_vad'},
        'reasoning': {'effort': 'none'},
        'audio': {
          'input': {
            'format': {'type': 'audio/pcm', 'rate': sampleRate},
            'transcription': {'language_hint': languageHint(languageCode)},
          },
          'output': {
            'format': {'type': 'audio/pcm', 'rate': sampleRate},
          },
        },
      },
    };
  }

  static Map<String, Object?> appendAudio(Uint8List pcm) {
    return {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm),
    };
  }

  static Map<String, Object?> cancel() => {'type': 'response.cancel'};

  /// El agente dice [text] y no añade otra frase.
  static List<Map<String, Object?>> say(String text, String languageCode) {
    return _userTurn('${_exactly(languageCode)} ${text.trim()}');
  }

  /// El visitante pide esto y el agente responde con las instrucciones de la sesión.
  static List<Map<String, Object?>> ask(String text) => _userTurn(text.trim());

  static List<Map<String, Object?>> _userTurn(String text) {
    return [
      {
        'type': 'conversation.item.create',
        'item': {
          'type': 'message',
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': text},
          ],
        },
      },
      {'type': 'response.create'},
    ];
  }

  static String _exactly(String languageCode) {
    final code = languageCode.trim().toLowerCase();
    if (code.startsWith('en')) return 'Say exactly this sentence and nothing else:';
    if (code.startsWith('de')) return 'Sage genau diesen Satz und sonst nichts:';
    if (code.startsWith('pt')) return 'Diga exatamente esta frase e nada mais:';
    return 'Di exactamente esta frase y nada más:';
  }

  /// Aviso de cortar o de interrumpir. No es un fallo de la API.
  static bool benignCancel(String text) {
    final blob = text.toLowerCase();
    if (blob.isEmpty) return false;
    const markers = <String>[
      'response_cancel_not_active',
      'no active response',
      'cancellation failed',
      'response.cancelled',
      'response.canceled',
      'response cancelled',
      'response canceled',
      'interrupt',
    ];
    for (final marker in markers) {
      if (blob.contains(marker)) return true;
    }
    return false;
  }

  static int? statusOf(String text) {
    final match = RegExp(
      r'(?:status(?:\s+code)?|http)\s*[:=]?\s*(\d{3})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  static XaiVoiceNotice interpret(Object? event, {String secret = ''}) {
    if (event is! Map) return const XaiVoiceNotice.ignore();
    final type = event['type']?.toString() ?? '';
    switch (type) {
      case 'session.updated':
        return const XaiVoiceNotice.ready();
      case 'input_audio_buffer.speech_started':
        return const XaiVoiceNotice.visitorStarted();
      case 'input_audio_buffer.speech_stopped':
      case 'input_audio_buffer.committed':
        return const XaiVoiceNotice.visitorStopped();
      case 'conversation.item.input_audio_transcription.delta':
        final delta = _piece(event);
        if (delta.isEmpty) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.visitorText(delta, replace: false, ended: false);
      case 'conversation.item.input_audio_transcription.updated':
        final live = _piece(event);
        if (live.isEmpty) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.visitorText(live, replace: true, ended: false);
      case 'conversation.item.input_audio_transcription.completed':
        final said = _piece(event);
        if (said.isEmpty) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.visitorText(said, replace: true, ended: true);
      case 'response.created':
        return const XaiVoiceNotice.guideStarted();
      case 'response.output_audio_transcript.delta':
      case 'response.audio_transcript.delta':
        final delta = _piece(event);
        if (delta.isEmpty) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.guideText(delta, replace: false);
      case 'response.output_audio_transcript.done':
      case 'response.audio_transcript.done':
        final full = event['transcript']?.toString().trim() ?? '';
        if (full.isEmpty) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.guideText(full, replace: true);
      case 'response.output_audio.delta':
      case 'response.audio.delta':
        final bytes = _audio(event['delta']);
        if (bytes == null || bytes.isEmpty) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.guideAudio(bytes);
      case 'response.done':
      case 'response.completed':
        return const XaiVoiceNotice.guideDone();
      default:
        final failure = _failure(event, type, secret);
        if (failure == null) return const XaiVoiceNotice.ignore();
        return XaiVoiceNotice.failed(failure);
    }
  }

  static XaiVoiceFailure? _failure(Map event, String type, String secret) {
    if (type != 'error' && !type.endsWith('.error')) return null;
    final error = event['error'];
    var code = '';
    var message = '';
    int? status;
    if (error is Map) {
      code = error['code']?.toString().trim() ?? '';
      message = error['message']?.toString().trim() ?? '';
      status = _asStatus(error['status'] ?? error['status_code']);
    } else if (error is String) {
      message = error.trim();
    }
    if (message.isEmpty) message = event['message']?.toString().trim() ?? '';
    if (benignCancel('$type $code $message')) return null;
    final detail = DeepSeekLog.safe(
      [code, message].where((part) => part.isNotEmpty).join(' '),
      secret,
    );
    status ??= statusOf(detail);
    status ??= _statusForCode(code);
    return XaiVoiceFailure(status: status, detail: detail);
  }

  static int? _asStatus(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static int? _statusForCode(String code) {
    final lower = code.toLowerCase();
    if (lower.contains('invalid_api_key') || lower.contains('unauthorized')) return 401;
    if (lower.contains('forbidden') || lower.contains('permission')) return 403;
    if (lower.contains('not_found') || lower.contains('model_not_found')) return 404;
    if (lower.contains('rate') || lower.contains('too_many')) return 429;
    return null;
  }

  static String _piece(Map event) {
    final transcript = event['transcript']?.toString().trim() ?? '';
    if (transcript.isNotEmpty) return transcript;
    final delta = event['delta']?.toString() ?? '';
    if (delta.trim().isNotEmpty) return delta;
    final text = event['text']?.toString().trim() ?? '';
    return text;
  }

  static Uint8List? _audio(Object? delta) {
    if (delta is! String || delta.isEmpty) return null;
    try {
      return base64Decode(delta);
    } catch (_) {
      return null;
    }
  }
}

/// Lo que la pantalla Hablar necesita del agente. Los tests ponen una copia falsa.
abstract class XaiVoiceSession {
  void Function(bool speaking)? onVisitor;
  void Function(String text, {required bool replace, required bool ended})? onVisitorText;
  void Function()? onVisitorStopped;
  void Function()? onGuideStart;
  void Function(String text, {required bool replace})? onGuideText;
  void Function()? onGuideDone;
  void Function(XaiVoiceFailure failure)? onFailure;

  Future<bool> start({
    required String apiKey,
    required String instructions,
    required String voice,
    required String languageCode,
  });

  Future<void> update({
    required String instructions,
    required String voice,
    required String languageCode,
  });

  Future<void> say(String text);

  Future<void> ask(String text);

  Future<void> interrupt();

  Future<void> close();

  void setMuted(bool muted);
}

/// Agente de voz de xAI por WebSocket. El micrófono y el altavoz van en PCM de 24 kHz.
class XaiRealtimeVoice implements XaiVoiceSession {
  XaiRealtimeVoice({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  WebSocket? _socket;
  StreamSubscription<Uint8List>? _mic;
  StreamSubscription<dynamic>? _events;
  final List<Uint8List> _pendingMic = [];
  int _pendingBytes = 0;
  final List<int> _samples = [];
  String _key = '';
  String _language = 'es';
  bool _ready = false;
  bool _muted = false;
  bool _closed = false;
  bool _playbackReady = false;
  bool _startingPlayback = false;
  bool _turnOpen = false;
  int _playGen = 0;

  static const _pendingCap = XaiRealtime.sampleRate * 2;

  @override
  void Function(bool speaking)? onVisitor;

  @override
  void Function(String text, {required bool replace, required bool ended})? onVisitorText;

  @override
  void Function()? onVisitorStopped;

  @override
  void Function()? onGuideStart;

  @override
  void Function(String text, {required bool replace})? onGuideText;

  @override
  void Function()? onGuideDone;

  @override
  void Function(XaiVoiceFailure failure)? onFailure;

  @override
  Future<bool> start({
    required String apiKey,
    required String instructions,
    required String voice,
    required String languageCode,
  }) async {
    await _reset();
    _closed = false;
    _key = apiKey.trim();
    _language = languageCode;
    if (_key.isEmpty) {
      onFailure?.call(const XaiVoiceFailure(detail: 'missing key'));
      return false;
    }
    try {
      final socket = await WebSocket.connect(
        XaiRealtime.endpoint.toString(),
        headers: {'Authorization': 'Bearer $_key'},
      );
      if (_closed) {
        await socket.close();
        return false;
      }
      _socket = socket;
      _events = socket.listen(_onRaw, onError: _onSocketError, onDone: _onSocketDone);
      _send(XaiRealtime.sessionUpdate(
        instructions: instructions,
        voice: voice,
        languageCode: languageCode,
      ));
      return true;
    } catch (error) {
      onFailure?.call(XaiVoiceFailure.from(error, _key));
      return false;
    }
  }

  @override
  Future<void> update({
    required String instructions,
    required String voice,
    required String languageCode,
  }) async {
    _language = languageCode;
    _send(XaiRealtime.sessionUpdate(
      instructions: instructions,
      voice: voice,
      languageCode: languageCode,
    ));
  }

  @override
  Future<void> say(String text) async {
    for (final message in XaiRealtime.say(text, _language)) {
      _send(message);
    }
  }

  @override
  Future<void> ask(String text) async {
    for (final message in XaiRealtime.ask(text)) {
      _send(message);
    }
  }

  @override
  Future<void> interrupt() async {
    _playGen++;
    _samples.clear();
    _turnOpen = false;
    _playbackReady = false;
    _send(XaiRealtime.cancel());
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }

  @override
  void setMuted(bool muted) => _muted = muted;

  @override
  Future<void> close() async {
    _closed = true;
    await _reset();
  }

  Future<void> _reset() async {
    _ready = false;
    _playGen++;
    _samples.clear();
    _pendingMic.clear();
    _pendingBytes = 0;
    _turnOpen = false;
    _playbackReady = false;
    final mic = _mic;
    _mic = null;
    await mic?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    final events = _events;
    _events = null;
    await events?.cancel();
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {}
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null || _closed) return;
    try {
      socket.add(jsonEncode(message));
    } catch (error) {
      onFailure?.call(XaiVoiceFailure.from(error, _key));
    }
  }

  void _onRaw(dynamic raw) {
    if (_closed || raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    final notice = XaiRealtime.interpret(decoded, secret: _key);
    switch (notice.kind) {
      case XaiVoiceNoticeKind.ignore:
        return;
      case XaiVoiceNoticeKind.ready:
        _ready = true;
        _flushMic();
        unawaited(_openMic());
      case XaiVoiceNoticeKind.visitorStarted:
        onVisitor?.call(true);
      case XaiVoiceNoticeKind.visitorStopped:
        onVisitor?.call(false);
        onVisitorStopped?.call();
      case XaiVoiceNoticeKind.visitorText:
        onVisitorText?.call(notice.text, replace: notice.replace, ended: notice.ended);
      case XaiVoiceNoticeKind.guideStarted:
        _turnOpen = true;
        onGuideStart?.call();
      case XaiVoiceNoticeKind.guideText:
        onGuideText?.call(notice.text, replace: notice.replace);
      case XaiVoiceNoticeKind.guideAudio:
        _takeAudio(notice.audio!);
      case XaiVoiceNoticeKind.guideDone:
        _turnOpen = false;
        _maybeFinish(_playGen);
      case XaiVoiceNoticeKind.failed:
        onFailure?.call(notice.failure!);
    }
  }

  void _onSocketError(Object error) {
    if (_closed) return;
    onFailure?.call(XaiVoiceFailure.from(error, _key));
  }

  void _onSocketDone() {
    if (_closed) return;
    onFailure?.call(const XaiVoiceFailure(offline: true));
  }

  Future<void> _openMic() async {
    if (_closed || _mic != null) return;
    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        onFailure?.call(const XaiVoiceFailure(microphone: true));
        return;
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: XaiRealtime.sampleRate,
          numChannels: 1,
        ),
      );
      _mic = stream.listen(_onMic, onError: (Object error) {
        onFailure?.call(XaiVoiceFailure.from(error, _key));
      });
    } catch (error) {
      onFailure?.call(XaiVoiceFailure.from(error, _key));
    }
  }

  void _onMic(Uint8List chunk) {
    if (_closed || _muted || chunk.isEmpty) return;
    if (!_ready || _socket == null) {
      _pendingMic.add(Uint8List.fromList(chunk));
      _pendingBytes += chunk.length;
      while (_pendingBytes > _pendingCap && _pendingMic.isNotEmpty) {
        _pendingBytes -= _pendingMic.removeAt(0).length;
      }
      return;
    }
    _send(XaiRealtime.appendAudio(chunk));
  }

  void _flushMic() {
    final waiting = List<Uint8List>.of(_pendingMic);
    _pendingMic.clear();
    _pendingBytes = 0;
    for (final chunk in waiting) {
      _send(XaiRealtime.appendAudio(chunk));
    }
  }

  void _takeAudio(Uint8List bytes) {
    if (bytes.length < 2) return;
    final view = ByteData.sublistView(bytes);
    final count = bytes.length ~/ 2;
    for (var i = 0; i < count; i++) {
      _samples.add(view.getInt16(i * 2, Endian.little));
    }
    unawaited(_ensurePlayback());
  }

  Future<void> _ensurePlayback() async {
    if (_closed || _playbackReady || _startingPlayback) {
      _feedQueued();
      return;
    }
    _startingPlayback = true;
    final generation = _playGen;
    try {
      await FlutterPcmSound.setup(sampleRate: XaiRealtime.sampleRate, channelCount: 1);
      await FlutterPcmSound.setFeedThreshold(XaiRealtime.sampleRate ~/ 10);
      FlutterPcmSound.setFeedCallback((remaining) {
        if (remaining > XaiRealtime.sampleRate ~/ 10) return;
        _feedQueued();
        if (remaining == 0) _maybeFinish(generation);
      });
      if (_closed || generation != _playGen) return;
      _playbackReady = true;
      _feedQueued();
      FlutterPcmSound.start();
    } catch (error) {
      if (!_closed) onFailure?.call(XaiVoiceFailure.from(error, _key));
    } finally {
      _startingPlayback = false;
    }
  }

  void _feedQueued() {
    if (_samples.isEmpty || !_playbackReady) return;
    final take = _samples.length > 4800 ? 4800 : _samples.length;
    final chunk = _samples.sublist(0, take);
    _samples.removeRange(0, take);
    final bytes = ByteData(chunk.length * 2);
    for (var i = 0; i < chunk.length; i++) {
      bytes.setInt16(i * 2, chunk[i], Endian.little);
    }
    unawaited(FlutterPcmSound.feed(PcmArrayInt16(bytes: bytes)));
  }

  void _maybeFinish(int generation) {
    if (generation != _playGen || _turnOpen || _samples.isNotEmpty || _closed) return;
    onGuideDone?.call();
  }
}
