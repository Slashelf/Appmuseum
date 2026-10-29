import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_route.dart';

/// Silencio que cierra la escucha del chat de texto.
const chatSilencePause = Duration(seconds: 3);

/// Si nadie habla, la pantalla Hablar deja de escuchar.
const voiceIdlePause = Duration(seconds: 20);

/// Tope para que el micrófono no quede abierto si el teléfono no detecta silencio.
const chatListenLimit = Duration(seconds: 60);

SpeechListenOptions chatListenOptions(String localeId) {
  return SpeechListenOptions(
    partialResults: true,
    cancelOnError: true,
    listenMode: ListenMode.dictation,
    pauseFor: chatSilencePause,
    listenFor: chatListenLimit,
    localeId: localeId,
  );
}

/// Mantener el micrófono no espera el silencio de 3 segundos: se corta al soltar.
SpeechListenOptions chatHoldListenOptions(String localeId) {
  return SpeechListenOptions(
    partialResults: true,
    cancelOnError: true,
    listenMode: ListenMode.dictation,
    pauseFor: chatListenLimit,
    listenFor: chatListenLimit,
    localeId: localeId,
  );
}

/// Hablar no deja que el reconocedor corte en el primer silencio.
/// La pantalla decide cuándo la frase terminó.
SpeechListenOptions voiceListenOptions(String localeId) {
  return SpeechListenOptions(
    partialResults: true,
    cancelOnError: false,
    listenMode: ListenMode.dictation,
    pauseFor: chatListenLimit,
    listenFor: chatListenLimit,
    localeId: localeId,
  );
}

typedef ChatWords = void Function(String words, bool isFinal);
typedef ChatLevel = void Function(double level);
typedef ChatStatus = void Function(String status);

/// Escucha del chat. En pruebas se sustituye por un doble.
abstract class ChatEar {
  Future<bool> prepare({
    required ChatStatus onStatus,
    required void Function() onError,
  });

  Future<void> listen({
    required ChatWords onWords,
    required ChatLevel onLevel,
    required String localeId,
    SpeechListenOptions? options,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// Voz que lee una respuesta. En pruebas se sustituye por un doble.
abstract class ChatSpeaker {
  Future<void> speak({
    required String text,
    required String languageCode,
    required void Function() onDone,
  });

  Future<void> stop();
}

class DeviceChatEar implements ChatEar {
  DeviceChatEar([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  Future<bool> prepare({
    required ChatStatus onStatus,
    required void Function() onError,
  }) async {
    try {
      return await _speech.initialize(
        onStatus: onStatus,
        onError: (_) => onError(),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> listen({
    required ChatWords onWords,
    required ChatLevel onLevel,
    required String localeId,
    SpeechListenOptions? options,
  }) {
    return _speech.listen(
      onResult: (result) => onWords(result.recognizedWords, result.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: options ?? chatListenOptions(localeId),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

/// Motor de lectura. Las pruebas sustituyen el de flutter_tts.
abstract class TtsEngine {
  Future<void> setLanguage(String language);

  Future<void> setSpeechRate(double rate);

  void bindFinish(void Function() finish);

  Future<void> speak(String text);

  Future<void> stop();
}

class _FlutterTtsEngine implements TtsEngine {
  _FlutterTtsEngine(this._voice);

  final FlutterTts _voice;
  bool _bound = false;

  @override
  Future<void> setLanguage(String language) async {
    await _voice.setLanguage(language);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _voice.setSpeechRate(rate);
  }

  @override
  void bindFinish(void Function() finish) {
    if (_bound) return;
    _bound = true;
    _voice.setCompletionHandler(finish);
    _voice.setCancelHandler(finish);
  }

  @override
  Future<void> speak(String text) async {
    await _voice.speak(text);
  }

  @override
  Future<void> stop() async {
    await _voice.stop();
  }
}

class DeviceChatSpeaker implements ChatSpeaker {
  DeviceChatSpeaker({TtsEngine? engine, Future<void> Function()? prepareRoute})
      : _engine = engine,
        _prepareRoute = prepareRoute;

  final TtsEngine? _engine;
  final Future<void> Function()? _prepareRoute;
  TtsEngine? _live;
  bool _bound = false;
  bool _arming = false;
  void Function()? _onDone;

  TtsEngine get _tts => _live ??= _engine ?? _FlutterTtsEngine(FlutterTts());

  void _finish() {
    if (_arming) return;
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> speak({
    required String text,
    required String languageCode,
    required void Function() onDone,
  }) async {
    try {
      await (_prepareRoute ?? SpeechRoute.prepare)();
    } catch (_) {}
    final engine = _tts;
    await engine.setLanguage(ttsLanguage(languageCode));
    await engine.setSpeechRate(0.45);
    if (!_bound) {
      engine.bindFinish(_finish);
      _bound = true;
    }
    final previous = _onDone;
    _onDone = null;
    _arming = true;
    try {
      if (previous != null) await engine.stop();
    } catch (_) {
      // La lectura anterior ya terminó.
    } finally {
      _arming = false;
    }
    previous?.call();
    _onDone = onDone;
    _arming = true;
    try {
      await engine.speak(text);
    } finally {
      _arming = false;
    }
  }

  @override
  Future<void> stop() async {
    final previous = _onDone;
    _onDone = null;
    _arming = true;
    try {
      await _live?.stop();
    } catch (_) {
      // El motor ya estaba parado.
    } finally {
      _arming = false;
    }
    previous?.call();
  }
}

String ttsLanguage(String languageCode) {
  switch (languageCode) {
    case 'en':
      return 'en-US';
    case 'pt':
      return 'pt-BR';
    case 'de':
      return 'de-DE';
    default:
      return 'es-ES';
  }
}

/// El reconocedor no usa la misma escala en todos los teléfonos.
double chatSoundLevel(double level) {
  if (level.isNaN) return 0;
  if (level < 0) return ((level + 50) / 50).clamp(0.0, 1.0);
  return (level / 10).clamp(0.0, 1.0);
}
